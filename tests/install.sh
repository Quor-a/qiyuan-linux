#!/usr/bin/env bash
# 装机与镜像专项测试：分区方案、fstab、引导器配置、装机脚本、镜像校验
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }

step "1. 分区方案生成与校验"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import disk as D
L = D.default_layout('/dev/sda', 100 * D.GiB, 8 * D.GiB)
v = D.validate(L, 100 * D.GiB)
assert v['ok'], v['errors']
assert not v['errors'], v['errors']
# 根分区必须存在、EFI 必须是 FAT32
assert any(p.mount == '/' for p in L.partitions)
efi = [p for p in L.partitions if p.is_efi]
assert efi and efi[0].fs == 'vfat'
print("方案合法，分区数:", len(L.partitions))
PYEOF
[ $? -eq 0 ] && ok "默认方案校验通过" || bad "方案校验失败"

step "2. swap 随内存自适应"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import disk as D
def swap_of(mem):
    L = D.default_layout('/dev/sda', 100 * D.GiB, mem)
    return next(p.size for p in L.partitions if p.is_swap)
cases = [(1 * D.GiB, 2 * D.GiB),    # 小内存 → 2 倍
         (4 * D.GiB, 4 * D.GiB),    # 中等 → 等量
         (16 * D.GiB, 8 * D.GiB),   # 较大 → 一半，上限 8G
         (128 * D.GiB, 4 * D.GiB)]  # 超大 → 固定 4G
for mem, expect in cases:
    got = swap_of(mem)
    assert abs(got - expect) < 16 * D.MiB, f"内存{mem//D.GiB}G 期望{expect//D.GiB}G 实得{got//D.GiB}G"
    print(f"  内存 {mem//D.GiB:>3}G → swap {got//D.GiB}G")
PYEOF
[ $? -eq 0 ] && ok "swap 按内存自适应" || bad "swap 计算不正确"

step "3. 危险方案必须被拒绝"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import disk as D
from dataclasses import replace

# 3a 磁盘太小
L = D.default_layout('/dev/sdb', 4 * D.GiB, 2 * D.GiB)
v = D.validate(L, 4 * D.GiB)
assert not v['ok'], "4G 盘装不下却判为可行"
print("  磁盘过小:", v['errors'][0][:40])

# 3b 没有根分区
L2 = D.Layout('/dev/sdb', [D.Partition('/home', 'ext4', D.GiB)])
v2 = D.validate(L2, 100 * D.GiB)
assert not v2['ok']
assert any('没有根分区' in e for e in v2['errors'])
print("  无根分区: 已拒绝")

# 3c EFI 分区太小
L3 = D.Layout('/dev/sdb', [
    D.Partition('/boot/efi', 'vfat', 100 * D.MiB, D.TYPE_EFI, ['boot', 'esp']),
    D.Partition('/', 'ext4', 20 * D.GiB)], uefi=True)
v3 = D.validate(L3, 100 * D.GiB)
assert not v3['ok']
assert any('FAT' in e or '260' in e or '规范' in e for e in v3['errors']), v3['errors']
print("  EFI 过小:", v3['errors'][0][:40])

# 3d EFI 用了错误的文件系统
L4 = D.Layout('/dev/sdb', [
    D.Partition('/boot/efi', 'ext4', 512 * D.MiB, D.TYPE_EFI, ['boot', 'esp']),
    D.Partition('/', 'ext4', 20 * D.GiB)], uefi=True)
v4 = D.validate(L4, 100 * D.GiB)
assert not v4['ok']
assert any('FAT32' in e for e in v4['errors'])
print("  EFI 非 FAT32: 已拒绝")

# 3e 多个分区都要占满剩余空间
L5 = D.Layout('/dev/sdb', [
    D.Partition('/', 'ext4', None),
    D.Partition('/home', 'ext4', None)])
v5 = D.validate(L5, 100 * D.GiB)
assert not v5['ok']
assert any('剩余空间' in e for e in v5['errors'])
print("  多个增长分区: 已拒绝")
PYEOF
[ $? -eq 0 ] && ok "五类危险方案全部被拒" || bad "危险方案未被检出"

step "4. fstab 用 UUID 而非设备名"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import disk as D
L = D.default_layout('/dev/sda', 100 * D.GiB, 8 * D.GiB)
fstab = D.render_fstab(L.partitions, {'/': 'UUID-A', '/boot': 'UUID-B',
                                      '/boot/efi': 'UUID-C', '/home': 'UUID-D'})
# 注释里会拿设备名当反面例子，只检查真正生效的行
active = "\n".join(l for l in fstab.splitlines() if not l.startswith('#'))
assert '/dev/' not in active, "fstab 生效行里出现了设备名，加装硬盘后会漂移"
assert 'UUID=UUID-A' in fstab and 'UUID=UUID-C' in fstab
# 根分区 fsck 顺序应为 1
for line in fstab.splitlines():
    if '\t/\t' in line:
        assert line.rstrip().endswith('\t1'), f"根分区 fsck 顺序不对: {line}"
print("fstab 全部使用 UUID，根分区 fsck 顺序为 1")
PYEOF
[ $? -eq 0 ] && ok "fstab 只用 UUID，根分区 fsck 顺序正确" || bad "fstab 不合格"

step "5. 内核命令行与 GRUB 配置"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import bootloader as BL
cmd = BL.kernel_cmdline('ROOT-UUID', 'ext4', resume_uuid='SWAP-UUID')
assert 'root=UUID=ROOT-UUID' in cmd, "root= 必须用 UUID"
assert 'resume=UUID=SWAP-UUID' in cmd
assert 'init=/sbin/init' in cmd
assert 'quiet' in cmd
print("  内核命令行:", cmd)

cfg = BL.grub_cfg('/vmlinuz', '/initramfs.img', cmd)
assert 'menuentry' in cfg
# 必须有一个非静默的救援项，起不来时看不到内核输出就等于瞎修
assert cfg.count('menuentry') >= 2, "缺少救援启动项"
assert 'initrd' in cfg
# 救援项里不该还有 quiet
lines = cfg.splitlines()
rescue_start = [i for i, l in enumerate(lines) if '救援' in l][0]
rescue_body = '\n'.join(lines[rescue_start:rescue_start + 4])
assert 'quiet' not in rescue_body, "救援项不应静默"
print("  GRUB 配置含救援项且救援项非静默")
PYEOF
[ $? -eq 0 ] && ok "内核命令行与 GRUB 配置正确（含非静默救援项）" || bad "引导配置不合格"

step "6. 生成的装机脚本语法正确且可执行"
rm -rf /tmp/qy-inst && ./bin/qydisk scripts --disk /dev/sda --size 100G \
  --memory 8G --out /tmp/qy-inst >/dev/null 2>&1
n=$(ls /tmp/qy-inst/*.sh 2>/dev/null | wc -l)
[ "$n" -eq 6 ] && ok "生成 6 个分步脚本" || bad "脚本数量不对（$n）"
syntax_ok=1
for f in /tmp/qy-inst/*.sh; do
  bash -n "$f" 2>/dev/null || { syntax_ok=0; echo "  语法错误: $f"; }
done
[ "$syntax_ok" -eq 1 ] && ok "全部脚本通过 bash 语法检查" || bad "脚本存在语法错误"

step "7. 分区脚本有防误删保护"
grep -q "确认请输入 yes" /tmp/qy-inst/1-partition.sh \
  && ok "清空磁盘前要求二次确认" || bad "缺少二次确认，会误删数据"
grep -q "wipefs" /tmp/qy-inst/1-partition.sh && ok "清除了旧文件系统签名" \
  || bad "未清除旧签名"

step "8. NVMe 与 SATA 设备名不能写错"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import disk as D
for disk, sep in (('/dev/sda', ''), ('/dev/nvme0n1', 'p'), ('/dev/mmcblk0', 'p')):
    L = D.default_layout(disk, 100 * D.GiB, 8 * D.GiB)
    s = D.render_mount_script(L)
    if sep:
        assert f'${{DISK}}{sep}4' in s, f"{disk} 应使用 {sep} 分隔"
    else:
        assert '${DISK}4' in s
    print(f"  {disk} → ${{DISK}}{sep}N")
PYEOF
[ $? -eq 0 ] && ok "NVMe/MMC 分区名带 p，SATA 不带" || bad "设备名生成错误"

step "9. 镜像构建与校验（如实标注跳过项）"
rm -rf /tmp/qy-root-img && ./bin/qypkg --root /tmp/qy-root-img \
  assemble filesystem qyinit >/dev/null 2>&1
./bin/qydisk image --disk /dev/sda --size 100G --image-size 64M \
  --out /tmp/qy-img.img --target /tmp/qy-root-img >/tmp/qy-img.log 2>&1
grep -q "镜像构建报告" /tmp/qy-img.log && ok "镜像构建完成" \
  || { bad "镜像构建失败"; head -5 /tmp/qy-img.log; }
[ -f /tmp/qy-img.img ] && ok "镜像文件已生成（$(du -h /tmp/qy-img.img | cut -f1)）" \
  || bad "镜像文件不存在"
./bin/qydisk verify --out /tmp/qy-img.img >/tmp/qy-vf.log 2>&1
grep -q "需要 loop 设备/root 权限" /tmp/qy-vf.log \
  && ok "需真实权限的检查被如实标注为跳过（未假装通过）" \
  || bad "校验未如实标注跳过项"

step "10. 空间不足时明确报错而非留下损坏镜像"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import image as IM
from pathlib import Path
try:
    # 请求远超可用空间的大小
    IM.build_disk_image(Path('/tmp/qy-root-img'), Path('/tmp/qy-huge.img'),
                        size=999 * 1024 * 1024 * 1024)
    print("ERROR: 超大镜像竟然创建成功")
    sys.exit(1)
except IM.ImageError as e:
    print("正确拒绝:", str(e).splitlines()[0])
except OSError as e:
    print("正确拒绝(OS):", e)
assert not Path('/tmp/qy-huge.img').exists(), "失败后不应留下损坏的镜像文件"
PYEOF
[ $? -eq 0 ] && ok "空间不足时报错且不留下损坏文件" || bad "空间不足处理不当"

step "11. 清理"
rm -rf /tmp/qy-inst /tmp/qy-root-img /tmp/qy-img.img /tmp/qy-img.log \
       /tmp/qy-vf.log /tmp/qy-disk.img
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
