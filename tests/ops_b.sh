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

step "5. 安装脚本：pre 失败要中止，post 失败不致命"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import pkgops as P
from pathlib import Path
# 正常脚本
r = P.run_script("post_install", "echo hello", Path("/tmp"), "x")
assert r.ok and "hello" in r.output, f"正常脚本没跑通: {r.error}"
print("  正常脚本 → ok")
# 失败脚本要报出错误
r = P.run_script("post_install", "exit 3", Path("/tmp"), "x")
assert not r.ok, "失败脚本竟返回成功"
print("  失败脚本 → 检出（退出码 3）")
# 卡住的脚本必须被限时终止，否则整个事务挂起
r = P.run_script("post_install", "sleep 60", Path("/tmp"), "x", timeout=3)
assert not r.ok and "秒" in r.error, f"超时未生效: {r.error}"
print("  卡住的脚本 → 3 秒后终止（不会挂起事务）")
PYEOF
[ $? -eq 0 ] && ok "脚本能执行、能检出失败、能限时" || bad "脚本处理不正确"

step "6. 触发器：按产物自动推断"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import pkgops as P
def mk(paths, trig=None):
    files = [type("F", (), {"path": p})() for p in paths]
    return type("M", (), {"files": files, "triggers": trig or []})()
# 装了字体 → 应触发 fonts
t = P.triggers_for(mk(["usr/share/fonts/TTF/x.ttf"]))
assert "fonts" in t, f"字体未触发: {t}"
print("  字体文件 → fonts")
t = P.triggers_for(mk(["usr/share/applications/x.desktop"]))
assert "desktop-database" in t, f"desktop 未触发: {t}"
print("  .desktop → desktop-database")
t = P.triggers_for(mk(["usr/share/man/man1/x.1"]))
assert "man-db" in t, f"man 未触发: {t}"
print("  手册页 → man-db")
t = P.triggers_for(mk(["usr/lib/libz.so.1.2.13"]))
assert "ldconfig" in t, f"so 未触发: {t}"
print("  共享库 → ldconfig")
t = P.triggers_for(mk(["usr/share/glib-2.0/schemas/x.gschema.xml"]))
assert "glib-schemas" in t, f"schema 未触发: {t}"
print("  GSettings → glib-schemas")
# 普通文件不该乱触发
t = P.triggers_for(mk(["usr/bin/foo", "usr/share/doc/x"]))
assert not t, f"普通文件被误触发: {t}"
print("  普通文件 → 不触发（无误报）")
PYEOF
[ $? -eq 0 ] && ok "五类触发器自动推断且无误报" || bad "触发器推断不正确"

step "7. 触发器是声明式的，不执行包自己的代码"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import pkgops as P
# 每个触发器都有固定命令和"为什么重要"的说明
for n, t in P.TRIGGERS.items():
    assert t["cmd"] and t["why"], f"{n} 缺 cmd 或 why"
    assert not t["cmd"].startswith("sh -c"), f"{n} 不该是任意代码"
print(f"  {len(P.TRIGGERS)} 个触发器全部是固定命令 + 说明")
PYEOF
[ $? -eq 0 ] && ok "触发器可审计（固定命令 + 说明）" || bad "触发器定义不完整"

step "8. alternatives：多包提供同一命令"
python3 - <<'PYEOF'
import sys, shutil; sys.path.insert(0, '.')
from qyos import pkgops as P
from pathlib import Path
root = Path("/tmp/qy-alt-root"); shutil.rmtree(root, ignore_errors=True)
root.mkdir(parents=True)
# gawk 和 mawk 都提供 awk
a = P.register_alt(root, "awk", "usr/bin/awk", "gawk", "usr/bin/gawk")
P.register_alt(root, "awk", "usr/bin/awk", "mawk", "usr/bin/mawk")
tgt = P.apply_alt(root, a)
print(f"  默认指向 {tgt}")
alts = P.load_alts(root)
assert len(alts["awk"]["providers"]) == 2, "两个提供者没都注册"
print("  两个提供者都已注册")
# 切换
new = P.set_alt(root, "awk", "mawk")
assert new == "usr/bin/mawk", f"切换失败: {new}"
print(f"  切换到 mawk → {new}")
link = root / "usr/bin/awk"
assert link.is_symlink(), "链接没建立"
# 卸载一个后应自动指向另一个
P.unregister_alt(root, "awk", "mawk")
d = P.load_alts(root)["awk"]
assert d["current"] == "gawk", f"卸载后未回退: {d['current']}"
print("  卸载 mawk → 自动回到 gawk")
try:
    P.set_alt(root, "awk", "nonexistent")
    raise AssertionError("选了不存在的提供者竟没报错")
except P.PkgOpsError as e:
    assert "可用" in str(e), "错误里没告诉有哪些可选"
    print("  选不存在的提供者 → 报错并列出可选")
PYEOF
[ $? -eq 0 ] && ok "alternatives 注册/切换/回退均正确" || bad "alternatives 不正确"

step "9. 系统用户：声明式且幂等"
python3 - <<'PYEOF'
import sys, shutil; sys.path.insert(0, '.')
from qyos import pkgops as P
from pathlib import Path
root = Path("/tmp/qy-sysu"); shutil.rmtree(root, ignore_errors=True)
(root/"etc").mkdir(parents=True)
(root/"etc"/"passwd").write_text("root:x:0:0:root:/root:/bin/sh\n")
(root/"etc"/"group").write_text("root:x:0:\n")
users = [P.SysUser("sshd", desc="SSH daemon"),
         P.SysUser("nginx", desc="web server"),
         P.SysUser("audio", group=True)]
done = P.apply_sysusers(root, users)
print(f"  创建: {done}")
assert any("sshd" in d for d in done), "sshd 未创建"
assert any("nginx" in d for d in done), "nginx 未创建"
assert any("audio" in d for d in done), "audio 组未创建"
# 幂等：再来一次不该重复创建
done2 = P.apply_sysusers(root, users)
assert not done2, f"重复执行又创建了一遍: {done2}"
print("  重复执行 → 无副作用（幂等）")
pw = (root/"etc"/"passwd").read_text()
assert "sshd" in pw and "nginx" in pw
# 纯组不该出现在 passwd 里
assert not any(l.startswith("audio:") for l in pw.splitlines()), \
    "纯组被写进了 passwd"
print("  纯组只进 group，不进 passwd")
PYEOF
[ $? -eq 0 ] && ok "系统用户可创建、幂等、组与用户分开" || bad "系统用户处理不正确"

step "10. 装真实包会触发对应动作"
qyrm "$TMP/root3"; mkdir -p "$TMP/root3"
./bin/qypkg --root "$TMP/root3" install libqydemo > "$TMP/inst.log" 2>&1
grep -q "已触发 ldconfig" "$TMP/inst.log" \
  && ok "装了 .so 自动触发 ldconfig" || bad "ldconfig 未触发"

step "11. 清理"
qyrm "$TMP" /tmp/qy-alt-root /tmp/qy-sysu
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1