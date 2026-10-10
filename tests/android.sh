#!/usr/bin/env bash
# 安卓设备适配专项测试：boot.img、动态分区、A/B 槽、内核片段、移动端形态
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/home/agentuser/qyw/.qy-android
mkdir -p "$TMP"

step "1. boot.img 打包与自检"
head -c 200000 /dev/zero > "$TMP/kernel"
head -c 50000 /dev/zero > "$TMP/ramdisk"
head -c 8000 /dev/zero > "$TMP/dtb"
./bin/qyandroid bootimg --kernel "$TMP/kernel" --ramdisk "$TMP/ramdisk" \
  --dtb "$TMP/dtb" --cmdline "console=tty0" --os-version 13.0.0 \
  --out "$TMP/boot.img" >/dev/null 2>&1 \
  && ok "打包成功且通过自检" || bad "打包失败"
./bin/qyandroid verify "$TMP/boot.img" >/dev/null 2>&1 \
  && ok "能重新解析并校验" || bad "无法解析自己打的包"

step "2. 自检必须抓出会变砖的问题"
python3 - <<PYEOF
import sys; sys.path.insert(0, '.')
from qyos import android as A
d = open("$TMP/boot.img", 'rb').read()
# 截断：刷进去必黑屏
assert A.verify_boot_image(d[:-1000]), "截断的镜像没被检出"
print("  截断 → 检出")
# 无 initramfs：切不了真根
bad = A.build_boot_image(A.BootImage(kernel=b'x'*100, ramdisk=b''))
assert A.verify_boot_image(bad), "缺 initramfs 没被检出"
print("  无 initramfs → 检出")
# 非法页大小
try:
    A.build_boot_image(A.BootImage(kernel=b'x', page_size=3000))
    raise AssertionError("非法页大小没被拒绝")
except A.AndroidError:
    print("  非法页大小 → 拒绝")
# 不是 boot.img
assert A.verify_boot_image(b'no'*100), "非镜像没被检出"
print("  非镜像 → 检出")
PYEOF
[ $? -eq 0 ] && ok "截断/缺 initramfs/页大小/非镜像 全部检出" || bad "自检有漏"

step "3. 各部分必须按页对齐"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import android as A
for page in (2048, 4096, 8192):
    img = A.BootImage(kernel=b'k'*12345, ramdisk=b'r'*6789,
                      dtb=b'd'*1000, page_size=page)
    d = A.build_boot_image(img)
    assert not A.verify_boot_image(d), f"页 {page} 自检未通过"
    assert len(d) % page == 0, f"总长不是页倍数: {len(d)} % {page}"
    info = A.parse_boot_image(d)
    assert info['page_size'] == page
    print(f"  页 {page}: 总长 {len(d)}（{len(d)//page} 页），对齐正确")
PYEOF
[ $? -eq 0 ] && ok "三种页大小都对齐且自检通过" || bad "页对齐不正确"

step "4. os_version 编码"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import android as A
# "13.0.0" 是 Android 版本不是年份。若误当年份解释会得到负数，
# 被 max(0,…) 夹成 0，于是所有镜像 os_version 都是 0
v = A.BootImage(os_version="13.0.0").os_version_field()
assert v != 0, "os_version 被编码成 0（年份解释错误）"
print(f"  Android 13 → {v} (0x{v:08x})")
# 年份形式也不该是 0
v2 = A.BootImage(os_version="2026.9.30").os_version_field()
assert v2 != 0
print(f"  2026.9.30 → {v2} (0x{v2:08x})")
# 非数字版本号要稳定（可复现构建）
a = A.BootImage(os_version="qiyuan-1.0").os_version_field()
b = A.BootImage(os_version="qiyuan-1.0").os_version_field()
assert a == b and a != 0
print(f"  qiyuan-1.0 → 稳定值 {a}")
PYEOF
[ $? -eq 0 ] && ok "Android 版本号不被误当年份" || bad "os_version 编码错误"

step "5. 动态分区布局"
./bin/qyandroid super --root-mb 3072 > "$TMP/super.txt" 2>&1
grep -q "system_a" "$TMP/super.txt" && grep -q "只读" "$TMP/super.txt" \
  && ok "system 子分区存在且只读（verified boot 要求）" || bad "子分区不对"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import android as A
lay = A.android_super_layout(3072)
cmd = lay.lpmake_cmd("/dev/block/by-name/super", lay.super_size())
# 子分区与组都必须带槽后缀，否则另一个槽用起来元数据会冲突
assert "system_a:" in cmd and "qiyuan_a" in cmd, f"缺槽后缀: {cmd}"
assert "--readonly" in cmd, "system 未标记只读"
assert "--metadata-slots" in cmd, "未指定元数据槽数"
print("  lpmake 命令含槽后缀与只读标记")
# super 大小必须容纳元数据 + 内容
assert lay.super_size() >= lay.metadata_total + lay.content_total()
print(f"  super {lay.super_size()//1024//1024}M ≥ 元数据+内容")
PYEOF
[ $? -eq 0 ] && ok "lpmake 命令正确且空间足够" || bad "动态分区不正确"

step "6. A/B 槽"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import android as A
s = A.SlotState(current="_a", other="_b")
n = s.switch()
assert n.current == "_b" and n.other == "_a", "切换后槽不对"
assert not n.current_ok, "新槽必须尚未标记为成功启动"
assert n.retry_left > 0, "新槽要有重试次数，否则一次启动失败就废了"
print(f"  _a → _b，重试次数 {n.retry_left}")
notes = A.ab_notes()
assert "A/B" in notes and "原子升级" in notes
PYEOF
[ $? -eq 0 ] && ok "槽切换正确且新槽有重试次数" || bad "A/B 槽逻辑不对"

step "7. 刷机脚本"
./bin/qyandroid flash --slot _a --out "$TMP/flash.sh" >/dev/null 2>&1
bash -n "$TMP/flash.sh" && ok "脚本语法正确" || bad "脚本语法错误"
grep -q "fastboot" "$TMP/flash.sh" && ok "使用 fastboot" || bad "不是 fastboot 脚本"
# 必须在 fastbootd 下刷动态分区，这是最常见卡住的一步
grep -q "reboot fastboot" "$TMP/flash.sh" \
  && ok "会先进 fastbootd（否则刷 super 失败）" || bad "未进 fastbootd"
grep -q "delete-logical-partition" "$TMP/flash.sh" \
  && ok "重建前先删旧逻辑分区" || bad "未清理旧布局"
grep -q "set_active" "$TMP/flash.sh" && ok "会切换活动槽" || bad "未切槽"
# 必须警告解锁会清数据
grep -q "解锁" "$TMP/flash.sh" && grep -q "清空" "$TMP/flash.sh" \
  && ok "明确警告解锁会清空数据" || bad "缺少刷机风险警告"
grep -q "set_active" "$TMP/flash.sh" && grep -q "回退" "$TMP/flash.sh" \
  && ok "提示了卡开机时如何回退" || bad "未说明回退方法"

step "8. 安卓 fstab 不能用 UUID"
./bin/qyandroid fstab > "$TMP/fstab" 2>&1
grep -q "by-name" "$TMP/fstab" && ok "用 /dev/block/by-name（按名字）" || bad "未用 by-name"
grep -q "^#" "$TMP/fstab" && grep -q "UUID" "$TMP/fstab" \
  && ok "解释了为什么不用 UUID" || bad "未说明原因"

step "9. 安卓内核片段"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import kernel as K
from pathlib import Path
txt = (Path("kernel/config") / "android.fragment").read_text()
items = K.parse_fragment(txt)
cfg = {}
cfg, _ = K.merge(cfg, [items])
# 关键项必须在（ION 已被上游删除，改用 DMA-BUF heaps）
for k in ("CONFIG_ANDROID_BINDER_IPC", "CONFIG_ANDROID_BINDERFS",
          "CONFIG_DMABUF_HEAPS", "CONFIG_DM_VERITY", "CONFIG_SECURITY_SELINUX",
          "CONFIG_ZRAM", "CONFIG_USB_CONFIGFS"):
    assert cfg.get(k) == "y", f"缺 {k}"
print("  Binder/DMA-BUF heaps/dm-verity/SELinux/zram/USB gadget 均在")
# 行内注释不能被当成值（会静默失效）
bad = [k for k, v in cfg.items() if "#" in str(v)]
assert not bad, f"值里混入了注释: {bad}"
print("  无行内注释污染值")
PYEOF
[ $? -eq 0 ] && ok "安卓内核片段内容正确" || bad "内核片段有问题"

step "10. aarch64 基线片段"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import kernel as K
from pathlib import Path
cfg = {}
for n in ("base-aarch64", "hardening", "android"):
    cfg, _ = K.merge(cfg, [K.parse_fragment(
        (Path("kernel/config") / f"{n}.fragment").read_text())])
r = K.validate(cfg, arch="aarch64", android=True)
assert not r["missing"], f"缺失: {[m['option'] for m in r['missing']]}"
assert not r["forbidden"], f"违规: {r['forbidden']}"
print(f"  {len(cfg)} 项配置，缺失 0，违规 0")
PYEOF
[ $? -eq 0 ] && ok "aarch64 完整配置通过校验" || bad "aarch64 配置有缺失"
# x86_64 基线不该因为安卓改动而退化
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import kernel as K
from pathlib import Path
cfg = {}
for n in ("base-x86_64", "hardening"):
    cfg, _ = K.merge(cfg, [K.parse_fragment(
        (Path("kernel/config") / f"{n}.fragment").read_text())])
r = K.validate(cfg, arch="x86_64")
assert not r["missing"], f"x86 缺失: {[m['option'] for m in r['missing']]}"
print(f"  x86_64 {len(cfg)} 项，缺失 0")
PYEOF
[ $? -eq 0 ] && ok "x86_64 未因安卓改动退化" || bad "x86_64 出现回归"

step "11. 内核逻辑矛盾能被检出"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import kernel as K
# 单项都合法但组合不成立：开 Binder 没开 ANDROID、开 zram 没开 zsmalloc
bad = {"CONFIG_ANDROID_BINDER_IPC": "y", "CONFIG_ZRAM": "y",
       "CONFIG_DM_VERITY": "y", "CONFIG_MODULES": "y", "CONFIG_64BIT": "y",
       "CONFIG_OF": "y", "CONFIG_ARM64": "y", "CONFIG_ANDROID_BINDERFS": "y",
       "CONFIG_ION": "y", "CONFIG_SECURITY_SELINUX": "y",
       "CONFIG_DEVTMPFS": "y", "CONFIG_USB_CONFIGFS": "y",
       "CONFIG_INPUT_TOUCHSCREEN": "y", "CONFIG_REGULATOR": "y"}
r = K.validate(bad, arch="aarch64", android=True)
assert r["notes"], "矛盾检测未生效"
for n in r["notes"]:
    print("  " + n[:66])
PYEOF
[ $? -eq 0 ] && ok "检出组合矛盾（单项合法但整体不成立）" || bad "矛盾检测无效"

step "12. 移动端形态"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import recipe as R, profile as PF, cycles as C
from qyos.deps import Universe
from pathlib import Path
rs = R.load_tree(Path('recipes'))
u = Universe()
for r in rs.values(): u.add(r)
p = PF.get("mobile")
miss = [x for x in p.all_packages()
        if x not in rs and u.provider_of_name(x) is None]
assert not miss, f"移动端形态引用了不存在的包: {miss}"
print(f"  mobile 引用 {len(p.all_packages())} 项，全部存在")
assert "android" in p.kernel_fragments, f"内核片段缺 android: {p.kernel_fragments}"
assert "base-aarch64" in p.kernel_fragments, "内核基线应是 aarch64"
print(f"  内核片段: {p.kernel_fragments}")
# zram 形态下要积极换出
assert p.sysctl.get("vm.swappiness") == 100, "zram 下 swappiness 应为 100"
print("  zram 场景的 swappiness 已设为 100")
# 实际展开
cp = C.plan(rs)
class W:
    def __init__(s, r, skip):
        s.name = r.name; s.version = r.version; s.release = r.release
        s.provides = r.provides
        s.depends = [d for d in (r.depends or []) if d not in skip]
        s.makedepends = [d for d in (r.makedepends or []) if d not in skip]
u2 = Universe()
for n, r in rs.items(): u2.add(W(r, set(cp.broken_deps.get(n, ()))))
total = len(u2.resolve(p.all_packages()))
assert total > 50, f"展开规模异常: {total}"
print(f"  实际会安装 {total} 个包")
PYEOF
[ $? -eq 0 ] && ok "移动端形态完整可展开" || bad "移动端形态有问题"

step "13. 五种形态全部可展开"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import recipe as R, profile as PF, cycles as C
from qyos.deps import Universe
from pathlib import Path
rs = R.load_tree(Path('recipes'))
cp = C.plan(rs)
class W:
    def __init__(s, r, skip):
        s.name = r.name; s.version = r.version; s.release = r.release
        s.provides = r.provides
        s.depends = [d for d in (r.depends or []) if d not in skip]
        s.makedepends = [d for d in (r.makedepends or []) if d not in skip]
u = Universe()
for n, r in rs.items(): u.add(W(r, set(cp.broken_deps.get(n, ()))))
for name, p in sorted(PF.PROFILES.items()):
    n = len(u.resolve(p.all_packages()))
    assert n >= len(p.all_packages())
    print(f"  {name:12s} 选 {len(p.all_packages()):3d} → 装 {n:3d}")
assert len(PF.PROFILES) == 5, f"形态数不对: {len(PF.PROFILES)}"
PYEOF
[ $? -eq 0 ] && ok "五种形态全部可展开" || bad "形态展开失败"

step "14. 清理"
rm -rf "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
