#!/usr/bin/env bash
# 依赖体系专项测试：自动依赖发现、provides 反查、大规模依赖图、重建闭包
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }

# 测试自己准备构建产物，不依赖外部跑过什么：
# 依赖前序命令的副作用 = 换个执行顺序就全红，且失败原因极难看出
step "0. 准备构建产物（保留中间目录供扫描）"
./bin/qybuild qydemo libqydemo --sign var/repo/keys/qiyuan --force --keep \
  >/dev/null 2>&1 && ok "演示包已构建（保留 destdir）" || bad "构建失败"

step "1. ELF 识别与 soname 读取"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import shlibdeps as S
from pathlib import Path
# 用系统自带的真实 ELF 验证
import shutil
ls = shutil.which('ls')
assert ls and S.is_elf(Path(ls)), "ls 应当是 ELF"
assert not S.is_elf(Path('README.md')), "文本文件不应判为 ELF"
names = S.needed_sonames(Path(ls))
assert 'libc.so.6' in names, f"ls 必然链接 libc: {names}"
print(f"  ls 依赖: {names}")
PYEOF
[ $? -eq 0 ] && ok "能识别 ELF 并读出 NEEDED 的 soname" || bad "ELF 分析不正确"

step "2. 包内自带的库不能算外部依赖"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import shlibdeps as S
from qyos import recipe as R
from qyos.deps import Universe
from qyos.builder import Builder
from pathlib import Path
b = Builder(Path('.'))
u = Universe()
for r in b.recipes.values(): u.add(r)
rec = b.recipes['qydemo']
dest = b.paths["work"] / "qydemo" / "dest"
res = S.scan_package(dest, rec, u, available={"qydemo", "libqydemo"})
# qydemo 链接 libqydemo.so.1，但它由 libqydemo 提供且不在本包内 → 应为外部依赖
assert 'libqydemo' in res.auto_deps, f"应解析出 libqydemo: {res.auto_deps}"
# 反向验证：包自己提供的 soname 必须排除
rec2 = b.recipes['libqydemo']
dest2 = b.paths["work"] / "libqydemo" / "dest"
if dest2.exists():
    r2 = S.scan_package(dest2, rec2, u, available=set(b.recipes))
    assert 'libqydemo' not in r2.auto_deps, "包不该依赖自己"
    print(f"  libqydemo 自身: auto_deps={r2.auto_deps}（不含自己）")
else:
    print("  libqydemo 无构建产物，跳过自身排除检查")
print(f"  qydemo: auto_deps={res.auto_deps}")
PYEOF
[ $? -eq 0 ] && ok "正确区分外部库与包内自带库" || bad "自身依赖排除不正确"

step "3. 自举前后自动依赖的正确切换"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import shlibdeps as S
from qyos.deps import Universe
from qyos.builder import Builder
from pathlib import Path
b = Builder(Path('.'))
u = Universe()
for r in b.recipes.values(): u.add(r)
rec = b.recipes['qydemo']
dest = b.paths["work"] / "qydemo" / "dest"
# 自举前：glibc 还没编出来，不能写成依赖否则求解器找不到包
before = S.scan_package(dest, rec, u, available={"qydemo", "libqydemo"})
assert "glibc" not in before.auto_deps, "自举前不该把 glibc 写成依赖"
assert "glibc" in before.host_provided.values(), "应记为宿主暂供"
# 自举后：glibc 进了仓库，同一段代码自动把它补上
after = S.scan_package(dest, rec, u, available={"qydemo", "libqydemo", "glibc"})
assert "glibc" in after.auto_deps, "自举后应自动补上 glibc"
assert not after.host_provided, "自举后不该再有宿主暂供"
print(f"  自举前: {before.auto_deps} + 宿主提供 {list(before.host_provided.values())}")
print(f"  自举后: {after.auto_deps}")
PYEOF
[ $? -eq 0 ] && ok "自举前由宿主提供，自举后自动转为真实依赖" || bad "自举阶段处理不正确"

step "4. provides 反查能力名"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import recipe as R
from qyos.deps import Universe
from pathlib import Path
u = Universe()
for r in R.load_tree(Path('recipes')).values(): u.add(r)
cases = [('libqydemo.so.1', 'libqydemo'), ('sh', 'bash'),
         ('pkg-config', 'pkgconf'), ('python3', 'python'),
         ('libz.so.1', 'zlib')]
for cap, want in cases:
    got = u.provider_of_name(cap)
    assert got == want, f"{cap} 期望 {want} 实得 {got}"
    print(f"  {cap:18s} → {got}")
PYEOF
[ $? -eq 0 ] && ok "能力名能反查到提供者（sh→bash 等）" || bad "provides 反查失败"

step "5. 自动依赖只加不删"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import shlibdeps as S
from qyos import recipe as R
from pathlib import Path
rec = R.load(Path('recipes/qydemo.py'))
rec.depends = ["libqydemo", "manual-dep-keep"]
class R2:
    auto_deps = ["glibc", "libqydemo"]
    resolved = {}; needed = {}
added = S.apply_auto_deps(rec, R2())
assert "manual-dep-keep" in rec.depends, "手工声明的依赖不能被删掉"
assert "glibc" in rec.depends, "自动发现的应补上"
assert added == ["glibc"], f"只报新增: {added}"
print(f"  最终 depends: {rec.depends}")
PYEOF
[ $? -eq 0 ] && ok "自动依赖只补不删，手工声明保留" || bad "自动依赖覆盖了手工声明"

step "6. 路径形式的 provides 要给出明确指引"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos.deps import parse_dep, DepError
try:
    parse_dep('/bin/sh')
    raise AssertionError('路径形式未被拒绝')
except DepError as e:
    msg = str(e)
    assert 'sh' in msg and 'provides' in msg, f"应指引改用包名: {msg}"
    print("  提示:", msg.splitlines()[1].strip()[:50])
PYEOF
[ $? -eq 0 ] && ok "路径 provides 报错并指引改用包名" || bad "路径依赖报错不含指引"

step "7. 大规模依赖图：真实规模下求解与分层"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import recipe as R
from qyos.deps import Universe
from pathlib import Path
from collections import defaultdict
rs = R.load_tree(Path('recipes'))
assert len(rs) >= 50, f"配方库规模不足: {len(rs)}"
u = Universe()
for r in rs.values(): u.add(r)
targets = ["python", "coreutils", "bash", "util-linux", "openssh",
           "man-db", "iproute2", "kmod", "e2fsprogs"]
order = u.resolve(targets)
print(f"  配方 {len(rs)} 个；装 {len(targets)} 个目标牵出 {len(order)} 个包")
assert len(order) >= 20, f"闭包规模异常: {len(order)}"
# 分层
levels = {}
for n in order:
    lv = 0
    for d in (rs[n].depends or []) + (rs[n].makedepends or []):
        if d in levels:
            lv = max(lv, levels[d] + 1)
    levels[n] = lv
depth = max(levels.values()) + 1
by = defaultdict(list)
for n, l in levels.items(): by[l].append(n)
print(f"  并行层数 {depth}")
for l in sorted(by):
    print(f"    第{l}层 ({len(by[l])}): {' '.join(sorted(by[l])[:6])}"
          f"{' …' if len(by[l]) > 6 else ''}")
assert depth >= 3, f"依赖深度异常: {depth}"
PYEOF
[ $? -eq 0 ] && ok "真实规模依赖图可求解且能分层并行" || bad "大规模依赖图有问题"

step "7b. 虚拟包名作为目标时必须展开"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import recipe as R, cycles as C
from qyos.deps import Universe
from pathlib import Path
rs = R.load_tree(Path('recipes'))
cp = C.plan(rs)
class W:
    def __init__(s, r, skip):
        s.name=r.name; s.version=r.version; s.release=r.release
        s.provides=r.provides
        s.depends=[d for d in (r.depends or []) if d not in skip]
        s.makedepends=[d for d in (r.makedepends or []) if d not in skip]
u = Universe()
for n, r in rs.items(): u.add(W(r, set(cp.broken_deps.get(n, ()))))
# ssh-server 是 openssh 提供的虚拟包名，作为目标时必须展开成 openssh 及其依赖
order = u.resolve(['ssh-server'])
assert 'openssh' in order, f"虚拟包名目标未展开: {order}"
assert len(order) > 1, f"展开后应有依赖: {order}"
print(f"  ssh-server → 展开为 {order}")
PYEOF
[ $? -eq 0 ] && ok "虚拟包名目标会展开成真实包" || bad "虚拟包名目标未展开"

step "7c. 循环依赖能一次性全找出并打破"
./bin/qybuild --cycles >/tmp/qy-cy.log 2>&1
grep -q "循环依赖" /tmp/qy-cy.log && ok "检出环并给出打破方案" \
  || { bad "环分析失败"; cat /tmp/qy-cy.log; }
grep -q "freetype 暂不依赖 harfbuzz" /tmp/qy-cy.log \
  && ok "按 cycle_break 声明断在 freetype 一侧" || bad "断开位置不对"
grep -q "第二轮需重编" /tmp/qy-cy.log && grep -q "freetype" /tmp/qy-cy.log \
  && ok "标记了第二轮必须重编的包" || bad "未标记重编"
python3 -c "
import sys; sys.path.insert(0,'.')
from qyos import recipe as R, cycles as C
from pathlib import Path
rs=R.load_tree(Path('recipes'))
cy=C.find_cycles(rs)
assert any('freetype' in c for c in cy), f'未找到环: {cy}'
print(f'  共 {len(cy)} 个环，Tarjan 一次找全')
" && ok "用强连通分量一次找出全部环" || bad "环检测不正确"

step "7d. 形态在真实规模下能展开"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import recipe as R, profile as PF, cycles as C
from qyos.deps import Universe
from pathlib import Path
rs = R.load_tree(Path('recipes'))
cp = C.plan(rs)
class W:
    def __init__(s, r, skip):
        s.name=r.name; s.version=r.version; s.release=r.release
        s.provides=r.provides
        s.depends=[d for d in (r.depends or []) if d not in skip]
        s.makedepends=[d for d in (r.makedepends or []) if d not in skip]
u = Universe()
for n, r in rs.items(): u.add(W(r, set(cp.broken_deps.get(n, ()))))
for name, prof in sorted(PF.PROFILES.items()):
    n = len(u.resolve(prof.all_packages()))
    assert n >= len(prof.all_packages()), f"{name} 展开数少于选中数"
    print(f"  {name:12s} 选 {len(prof.all_packages()):3d} → 装 {n:3d}")
# 服务器形态必须真的包含 ssh、日志、时间同步
srv = u.resolve(PF.get('server').all_packages())
for want in ('openssh', 'syslog-ng', 'chrony'):
    assert want in srv, f"服务器形态缺少 {want}"
print("  服务器形态含 openssh/syslog-ng/chrony")
PYEOF
[ $? -eq 0 ] && ok "四种形态在 166 包规模下都能展开" || bad "形态展开失败"

step "8. 循环依赖能被检出"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos.deps import Universe, DepError
from qyos import bootstrap as BS
# 构造 a→b→a 的环
class P:
    def __init__(s, n, deps): s.name, s.version, s.release = n, "1.0", 1
    depends, makedepends, provides = [], [], []
u = Universe()
a, b = P('a', ['b']), P('b', ['a'])
a.depends = ['b']; b.depends = ['a']
u.add(a); u.add(b)
try:
    u.resolve(['a'])
    raise AssertionError('循环依赖未被检出')
except DepError as e:
    assert '环' in str(e) or '循环' in str(e), f"报错应说明是环: {e}"
    print("  检出:", str(e)[:60])
PYEOF
[ $? -eq 0 ] && ok "构造的循环依赖被检出" || bad "循环依赖未检出"

step "9. 重建闭包在真实规模上正确"
./bin/qysec rebuild --changed ncurses >/tmp/qy-rb2.log 2>&1
n=$(grep -c "^  " /tmp/qy-rb2.log)
[ "$n" -ge 10 ] && ok "改 ncurses 牵连 $n 个包重编" \
  || { bad "重建闭包规模异常（$n）"; cat /tmp/qy-rb2.log; }
grep -q "bash" /tmp/qy-rb2.log && grep -q "python" /tmp/qy-rb2.log \
  && ok "闭包包含 bash 与 python" || bad "闭包内容不对"
./bin/qysec rebuild --changed openssl >/tmp/qy-rb3.log 2>&1
grep -q "openssh" /tmp/qy-rb3.log && grep -q "curl" /tmp/qy-rb3.log \
  && ok "改 openssl 牵出 openssh 与 curl" || bad "openssl 闭包不对"

step "10. 审计命令可用"
./bin/qybuild --shlibdeps qydemo >/tmp/qy-sd.log 2>&1
grep -q "扫描" /tmp/qy-sd.log && grep -q "libqydemo" /tmp/qy-sd.log \
  && ok "审计输出了产物链接的库与提供者" \
  || { bad "审计输出不对"; cat /tmp/qy-sd.log; }

step "11. 清理"
rm -f /tmp/qy-rb2.log /tmp/qy-rb3.log /tmp/qy-sd.log
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
