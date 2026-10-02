#!/usr/bin/env bash
# 包级系统操作专项测试：配置保护、脚本、触发器、alternatives、系统用户
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-ops
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

# 测试会改 filesystem 的版本号。中断后不恢复的话，
# 下一次运行的基线全错（症状是一堆莫名其妙的失败），
# 所以用 trap 保证怎么退出都恢复
restore_ver(){ python3 tests/_restore_ver.py 2>/dev/null; qyrm recipes/__pycache__ 2>/dev/null; }
trap restore_ver EXIT INT TERM
restore_ver

# 测试会改 filesystem 的版本号。中断后不恢复的话，
# 下一次运行的基线全错（症状是一堆莫名其妙的失败），
# 所以用 trap 保证怎么退出都恢复
restore_ver(){ python3 tests/_restore_ver.py 2>/dev/null; qyrm recipes/__pycache__ 2>/dev/null; }
trap restore_ver EXIT INT TERM
restore_ver

step "1. 配置文件三方比对：四种情形"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import pkgops as P
cases = [
    ("首次安装", None, None, "NEW", "replace"),
    ("用户没改，包改了", "OLD", "OLD", "NEW", "replace"),
    ("用户改了，包没改", "MINE", "OLD", "OLD", "keep"),
    ("两边都改了", "MINE", "OLD", "NEW", "conflict"),
]
for desc, disk, old, new, want in cases:
    st = P.classify_config(disk, old, new)
    assert st.action == want, f"{desc}: 得到 {st.action}，应 {want}"
    print(f"  {desc:<16} → {st.action}")
# 旧版本没标配置文件（无原始校验和）时也要保守
st = P.classify_config("ANY", None, "NEW")
assert st.action == "conflict", "无法判断时应当保守"
print("  旧版本无记录      → conflict（保守，不覆盖）")
PYEOF
[ $? -eq 0 ] && ok "四种情形判定全部正确" || bad "三方比对逻辑不正确"

step "2. 打包时能标记配置文件"
qyrm var/work var/pkgs var/repo/x86_64
./bin/qybuild filesystem qyinit libqydemo qydemo \
  --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import format as F
from pathlib import Path
p = F.read_package(Path('var/pkgs/filesystem-0.1.0-1.x86_64.qyp'))
cfg = [f for f in p.meta.files if getattr(f, "config", False)]
assert cfg, "没有标记出任何配置文件"
names = {f.path for f in cfg}
for want in ("etc/fstab", "etc/hosts", "etc/profile", "etc/passwd"):
    assert want in names, f"{want} 未标记为配置文件"
print(f"  标记了 {len(cfg)} 个: {' '.join(sorted(names))}")
# 非 /etc 的文件不能被误标
plain = [f for f in p.meta.files if not getattr(f, "config", False)]
assert plain, "全部被标成配置了"
print(f"  其余 {len(plain)} 个文件未标记（无误标）")
PYEOF
[ $? -eq 0 ] && ok "配置文件能标记且不误标" || bad "配置标记不正确"

step "3. 升级：改过的保留、没改的升级（端到端）"
qyrm "$TMP/root"; mkdir -p "$TMP/root"
python3 tests/_set_ver.py 0.1.0
qyrm var/work var/pkgs var/repo/x86_64
./bin/qybuild filesystem --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
./bin/qypkg --root "$TMP/root" install filesystem >/dev/null 2>&1
[ -f "$TMP/root/etc/fstab" ] && ok "装上了 fstab" || bad "fstab 缺失"
# 管理员改 fstab，但不动 os-release
python3 -c "
import pathlib
pathlib.Path('$TMP/root/etc/fstab').write_text('# 我加的一块盘\\n')
"
# 升到 0.2.0：os-release 内容随版本变化，fstab 不变
python3 tests/_set_ver.py 0.2.0
qyrm recipes/__pycache__ var/work
./bin/qybuild filesystem --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
./bin/qypkg --root "$TMP/root" upgrade > "$TMP/up.log" 2>&1
grep -q "我加的一块盘" "$TMP/root/etc/fstab" \
  && ok "用户改过的 fstab 被保留" || bad "用户配置被覆盖"
grep -q 'VERSION_ID="0.2.0"' "$TMP/root/etc/os-release" \
  && ok "未改过的 os-release 正常升级" || bad "未改过的配置没升级"
[ ! -f "$TMP/root/etc/fstab.qynew" ] \
  && ok "包没改的文件不产生 .qynew（无虚假冲突）" || bad "产生了虚假冲突"
grep -q "冲突 0" "$TMP/up.log" \
  && ok "日志报告 0 冲突" || bad "冲突统计不对"

step "4. 两边都改了才提示合并"
# 用户改了 os-release，新版也改了它 → 真冲突
python3 -c "
import pathlib
p = pathlib.Path('$TMP/root/etc/os-release')
p.write_text(p.read_text() + 'MY_CUSTOM=1\\n')
"
python3 tests/_set_ver.py 0.3.0
qyrm recipes/__pycache__ var/work
./bin/qybuild filesystem --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
./bin/qypkg --root "$TMP/root" upgrade > "$TMP/up2.log" 2>&1
grep -q "MY_CUSTOM=1" "$TMP/root/etc/os-release" \
  && ok "冲突时保留用户的版本" || bad "用户的版本被覆盖"
[ -f "$TMP/root/etc/os-release.qynew" ] \
  && ok "新版本另存为 .qynew 供合并" || bad "未提供新版本"
grep -q "请自行合并" "$TMP/up2.log" \
  && ok "提示了怎么合并" || bad "未提示合并方法"
python3 tests/_set_ver.py 0.1.0
qyrm recipes/__pycache__ var/work
./bin/qybuild filesystem --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1

echo
echo "分段通过 $PASS 项，失败 $FAIL 项"
[ "$FAIL" -eq 0 ] || exit 1
