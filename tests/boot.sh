#!/usr/bin/env bash
# 自举与启动专项测试：内核配置片段、initramfs、自举闭环分析、校验和门禁
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }

step "1. 内核配置片段合并与校验"
./bin/qybuild --kernel-config --arch x86_64 \
  --fragment kernel/config/base-x86_64.fragment \
  --fragment kernel/config/hardening.fragment \
  --fragment kernel/config/container.fragment \
  --out /tmp/qy-kconfig >/tmp/qy-kc.log 2>&1
grep -q "内核配置校验全部通过" /tmp/qy-kc.log && ok "三片段合并后校验通过" \
  || { bad "校验未通过"; cat /tmp/qy-kc.log; }
n=$(grep -c "^CONFIG_" /tmp/qy-kconfig)
[ "$n" -gt 50 ] && ok "生成 $n 项配置" || bad "配置项太少（$n）"
grep -q "^CONFIG_BLK_DEV_INITRD=y" /tmp/qy-kconfig && ok "initramfs 支持已开启" \
  || bad "缺 BLK_DEV_INITRD（没有它切不了真根）"
grep -q "^CONFIG_STACKPROTECTOR_STRONG=y" /tmp/qy-kconfig && ok "加固项已开启" \
  || bad "加固项未开启"

step "2. 校验能检出危险配置"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import kernel as K
from pathlib import Path
frags = [K.parse_fragment(Path(f).read_text())
         for f in ('kernel/config/base-x86_64.fragment',
                   'kernel/config/hardening.fragment')]
cfg, _ = K.merge({}, frags)
cfg['CONFIG_BLK_DEV_INITRD'] = 'n'      # 切不了真根
cfg['CONFIG_MODULES'] = 'n'             # 驱动全废
cfg['CONFIG_EXT4_FS'] = 'm'             # 与 MODULES=n 矛盾
r = K.validate(cfg, 'x86_64')
assert not r['ok'], '应当判定为不通过'
names = [m['option'] for m in r['missing']]
assert 'CONFIG_BLK_DEV_INITRD' in names and 'CONFIG_MODULES' in names
assert any('MODULES=n' in n for n in r['notes']), '应提示配置自相矛盾'
print('检出:', names)
PYEOF
[ $? -eq 0 ] && ok "能检出缺失必需项与自相矛盾的配置" || bad "危险配置未被检出"

step "3. initramfs 构建与检视"
./bin/qybuild --initramfs --out /tmp/qy-ir.img >/tmp/qy-ir.log 2>&1
grep -q "initramfs 已生成" /tmp/qy-ir.log && ok "initramfs 构建成功" \
  || { bad "构建失败"; cat /tmp/qy-ir.log; }
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import initramfs as I
from pathlib import Path
info = I.inspect(Path('/tmp/qy-ir.img'))
assert info['bootable'], f"不可启动: {info['problems']}"
assert info['static_init'] is True, "早期 init 必须静态链接"
names = {i['name'] for i in info['items']}
for d in ('init', 'proc', 'sys', 'dev', 'newroot'):
    assert d in names, f"缺少 /{d}"
print(f"条目 {info['count']}，静态 init={info['static_init']}")
PYEOF
[ $? -eq 0 ] && ok "内容完整且 /init 为静态链接（真根挂载前无动态库）" \
  || bad "initramfs 内容不合格"

step "4. 破损的 initramfs 必须被判为不可启动"
python3 - <<'PYEOF'
import sys, gzip, shutil; sys.path.insert(0, '.')
from qyos import initramfs as I
from pathlib import Path
# 手工造一个缺 /init 的归档，检视必须报错
import io, stat
buf = io.BytesIO()
buf.write(I._pad(I._cpio_header("proc", stat.S_IFDIR | 0o755, 0, 1), 4))
buf.write(I._pad(I._cpio_header("TRAILER!!!", stat.S_IFREG | 0o644, 0, 2), 4))
p = Path('/tmp/qy-bad.img')
with open(p, 'wb') as f:
    g = gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0)
    g.write(buf.getvalue()); g.close()
info = I.inspect(p)
assert not info['bootable'], "缺 /init 却判为可启动"
assert any('缺少 /init' in x for x in info['problems'])
print('正确拒绝:', info['problems'])
PYEOF
[ $? -eq 0 ] && ok "缺 /init 的归档被正确判为不可启动" || bad "破损归档未被检出"

step "5. 自举：构建闭包与循环依赖检测"
./bin/qybuild --bootstrap >/tmp/qy-bs.log 2>&1
grep -q "构建闭包" /tmp/qy-bs.log && ok "自举分析可运行" \
  || { bad "分析失败"; cat /tmp/qy-bs.log; }
grep -q "工具链核心 4/4" /tmp/qy-bs.log && ok "工具链核心包齐备" \
  || bad "工具链核心包缺失"
grep -q "第二遍" /tmp/qy-bs.log && ok "已按自举阶段分批" || bad "未分阶段"

step "6. 构建依赖成环必须被检出"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import bootstrap as B

class FakeRecipe:
    def __init__(self, name, mk):
        self.name, self.makedepends, self.version, self.release = name, mk, "1", 1

recipes = {"a": FakeRecipe("a", ["b"]), "b": FakeRecipe("b", ["a"])}
cycles = B.detect_cycles(recipes)
assert cycles, "成环却没检出"
print("检出环:", cycles)

# 闭包计算遇到环必须报错，不能无限递归
try:
    B.build_closure(recipes, ["a"])
    print("ERROR: 成环时闭包计算没报错")
    sys.exit(1)
except B.BootstrapError as e:
    assert "循环" in str(e)
    print("闭包报错:", e)
PYEOF
[ $? -eq 0 ] && ok "循环依赖被检出且闭包计算不会无限递归" || bad "成环处理不正确"

step "7. 外部构建依赖缺失要如实报出"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import bootstrap as B
from qyos import recipe as R
from pathlib import Path
recipes = R.load_tree(Path('recipes'))
p = B.plan(recipes)
rd = p['readiness']
missing = rd['missing_makedepends']
# 工具链包依赖宿主提供的东西（不在配方库里），应当被如实记录
print('缺失构建依赖:', sorted({m['needs'] for m in missing}) or '无')
print('阻塞项:', rd['blockers'] or '无')
assert isinstance(rd['total'], int) and rd['total'] > 0
PYEOF
[ $? -eq 0 ] && ok "自举阻塞项如实报出" || bad "阻塞项分析失败"

step "8. 远程源码缺校验和时拒绝构建（供应链门禁）"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import recipe as R
from pathlib import Path
rec = R.load(Path('recipes/gcc.py'))
assert rec.checksum_pending, "gcc 配方应标记为校验和待补"
from qyos import builder as B
b = B.Builder(Path('.'), jobs=1)
try:
    b.check_buildable(rec)
    print("ERROR: 未校验的远程源码竟然允许构建")
    sys.exit(1)
except B.BuildError as e:
    assert 'sha256' in str(e)
    print("正确拒绝:", str(e).splitlines()[0])
PYEOF
[ $? -eq 0 ] && ok "缺 sha256 的大包被明确拒绝构建" || bad "校验和门禁失效"

step "9. 工具链大包不进普通全量构建"
./bin/qybuild all --force -q >/tmp/qy-all.log 2>&1
grep -q "跳过 gcc" /tmp/qy-all.log && ok "全量构建默认跳过需真实构建机的包" \
  || bad "工具链大包被误纳入"
grep -q "跳过 glibc" /tmp/qy-all.log && ok "glibc 同样被跳过" || bad "glibc 未被跳过"

step "10. 清理"
rm -f /tmp/qy-kconfig /tmp/qy-ir.img /tmp/qy-bad.img /tmp/qy-kc.log \
      /tmp/qy-ir.log /tmp/qy-bs.log /tmp/qy-all.log
rm -rf /tmp/qy-ir-build
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
