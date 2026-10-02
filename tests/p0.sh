#!/usr/bin/env bash
# P0 四项专项测试：固件、PAM、sudo、locale
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-p0
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. linux-firmware：装机镜像必须带 wifi 与 gpu"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
import importlib.util
spec = importlib.util.spec_from_file_location("fw", "recipes/linux-firmware.py")
fw = importlib.util.module_from_spec(spec); spec.loader.exec_module(fw)
# 笔记本不带 wifi 固件就是联网都做不到；
# 独显机器不带 gpu 进不了图形界面
for must in ("wifi", "gpu", "core", "net", "storage"):
    assert must in fw.IMAGE_GROUPS, f"装机镜像缺 {must} 组"
print(f"  镜像带: {' '.join(fw.IMAGE_GROUPS)}")
# 每组都要真有内容，不能是空壳
for g in fw.IMAGE_GROUPS:
    assert fw.GROUPS.get(g), f"{g} 组为空"
print(f"  每组都有内容: "
      f"{ {g: len(fw.GROUPS[g]) for g in fw.IMAGE_GROUPS} }")
# CPU 微码必须在 core 里：不装会有未修复的 CPU 漏洞
assert "amd-ucode" in fw.GROUPS["core"], "缺 AMD 微码"
assert "intel-ucode" in fw.GROUPS["core"], "缺 Intel 微码"
print("  CPU 微码在 core 组（缺了会有未修复的 CPU 漏洞）")
PYEOF
[ $? -eq 0 ] && ok "固件分组完整，wifi/gpu 在镜像内" || bad "固件分组不完整"

step "2. 固件目录名变了必须构建期就暴露"
python3 - <<'PYEOF'
import sys, tempfile, shutil; sys.path.insert(0, '.')
import importlib.util, pathlib
spec = importlib.util.spec_from_file_location("fw", "recipes/linux-firmware.py")
fw = importlib.util.module_from_spec(spec); spec.loader.exec_module(fw)

class FakeCtx:
    def __init__(self, srcdir): self.srcdir = srcdir; self.logged = []
    def log(self, m): self.logged.append(m)

# 源码树里缺目录 → 必须抛错，不能静默跳过。
# 静默跳过的后果是装机后网卡不工作，而那时用户已经格了盘
root = pathlib.Path(tempfile.mkdtemp())
(root/"amd-ucode").mkdir()
try:
    fw.build(FakeCtx(str(root)))
    raise AssertionError("缺目录竟然没报错")
except RuntimeError as e:
    assert "拒绝构建" in str(e), f"错误信息不对: {e}"
    print(f"  缺目录 → 构建期报错: {str(e)[:50]}…")
PYEOF
[ $? -eq 0 ] && ok "固件缺失在构建期暴露而非装机后" || bad "缺失被静默跳过"

step "3. PAM：没配置 = 装了库也不工作"
qyrm "$TMP/pam"; mkdir -p "$TMP/pam"
./bin/qypam --root "$TMP/pam" check > "$TMP/pam0.txt" 2>&1
grep -q "没有 /etc/pam.d" "$TMP/pam0.txt" \
  && ok "无 pam.d 时明确报出会全部认证失败" || bad "未报出"
./bin/qypam --root "$TMP/pam" apply >/dev/null 2>&1
./bin/qypam --root "$TMP/pam" check >/dev/null 2>&1 \
  && ok "生成后配置完整" || bad "生成后仍有缺失"

step "4. PAM：other 是兜底，缺了会拒绝所有认证"
rm -f "$TMP/pam/etc/pam.d/other"
./bin/qypam --root "$TMP/pam" check > "$TMP/pam1.txt" 2>&1
grep -q "缺 /etc/pam.d/other" "$TMP/pam1.txt" \
  && grep -q "直接拒绝认证" "$TMP/pam1.txt" \
  && ok "检出 other 缺失并说明后果" || bad "未检出 other 缺失"
./bin/qypam --root "$TMP/pam" apply >/dev/null 2>&1

step "5. PAM：口令强度与资源限制不能少"
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path('/tmp/qy-p0/pam/etc/pam.d/passwd')
p.write_text(p.read_text().replace('pam_pwquality.so', 'pam_unix.so'))
s = pathlib.Path('/tmp/qy-p0/pam/etc/pam.d/system-auth')
s.write_text(s.read_text().replace('pam_limits.so', 'pam_env.so'))
print("  已去掉 pwquality 与 limits")
PYEOF
./bin/qypam --root "$TMP/pam" check > "$TMP/pam2.txt" 2>&1
grep -q "空口令或 123456" "$TMP/pam2.txt" \
  && ok "缺口令强度会报出具体后果" || bad "未检出口令强度缺失"
grep -q "fork 炸弹" "$TMP/pam2.txt" \
  && ok "缺资源限制会报出具体后果" || bad "未检出资源限制缺失"
./bin/qypam --root "$TMP/pam" apply >/dev/null 2>&1

step "6. PAM：失败锁定必须存在（否则可无限猜密码）"
grep -q "pam_faillock" "$TMP/pam/etc/pam.d/other" \
  && grep -q "deny=5" "$TMP/pam/etc/pam.d/other" \
  && ok "配置了失败锁定（5 次锁 15 分钟）" || bad "无失败锁定"
# account 阶段的 faillock 是必要的（要能显示"已锁定"），
# 真正会把人锁死的是 auth 阶段的 authfail
grep -qE "auth.*pam_faillock.*authfail" "$TMP/pam/etc/pam.d/passwd" \
  && bad "改口令会触发失败锁定（用户会锁死自己）" \
  || ok "passwd 的 auth 阶段无失败锁定（避免锁死自己）"
grep -qE "account.*pam_faillock" "$TMP/pam/etc/pam.d/passwd" \
  && ok "passwd 保留 account 阶段（能显示已锁定）" \
  || bad "passwd 的 account 阶段缺 faillock"

step "7. sudo：依赖 PAM，且默认给 wheel 组"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
import importlib.util
spec = importlib.util.spec_from_file_location("su", "recipes/sudo.py")
su = importlib.util.module_from_spec(spec); spec.loader.exec_module(su)
# 没有 PAM 的 sudo 编译不出来，勉强编出来也无法做口令认证
assert "pam" in su.depends and "pam" in su.makedepends, \
    f"sudo 未声明依赖 PAM: {su.depends}"
print("  sudo 声明依赖 PAM（无 PAM 无法做口令认证）")
assert su.ADMIN_GROUP in ("wheel", "sudo"), f"管理员组不合理: {su.ADMIN_GROUP}"
print(f"  管理员组: {su.ADMIN_GROUP}")
PYEOF
[ $? -eq 0 ] && ok "sudo 依赖与管理员组正确" || bad "sudo 配方不正确"

step "8. sudoers：env_reset 与日志必须开，requiretty 必须关"
python3 - <<'PYEOF'
import sys, re; sys.path.insert(0, '.')
import importlib.util, pathlib
spec = importlib.util.spec_from_file_location("su", "recipes/sudo.py")
su = importlib.util.module_from_spec(spec); spec.loader.exec_module(su)
# 从配方里取出生成的 sudoers 文本做检查
src = pathlib.Path("recipes/sudo.py").read_text()
assert "Defaults env_reset" in src, "缺 env_reset"
print("  env_reset 已开（不清环境变量可被 LD_PRELOAD 提权）")
assert "logfile" in src, "缺日志"
print("  日志已开（无日志的 sudo 等于没有审计）")
# 只看实际生成的 sudoers 正文（""" 之间），
# 遍历整个源码会把 docstring 里的说明文字也当成配置
body = src.split('"""')[4] if src.count('"""') >= 5 else ""
for line in body.splitlines():
    st = line.strip()
    if "requiretty" in st and not st.startswith("#"):
        raise AssertionError(f"requiretty 被启用了: {st}")
print("  requiretty 已关闭（开了会让脚本与自动化全部失效）")
assert "secure_path" in src, "缺 secure_path"
print("  secure_path 已设")
PYEOF
[ $? -eq 0 ] && ok "sudoers 关键项全部正确" || bad "sudoers 配置有风险项"

step "9. locale：未设置 LANG 会明确报出乱码后果"
qyrm "$TMP/loc"; mkdir -p "$TMP/loc"
./bin/qylocale --root "$TMP/loc" check > "$TMP/loc0.txt" 2>&1
grep -q "没有设置 LANG" "$TMP/loc0.txt" \
  && grep -q "问号" "$TMP/loc0.txt" \
  && ok "未设 LANG 时报出乱码后果" || bad "未报出或说明不清"

step "10. locale：设置与生成必须一步完成"
./bin/qylocale --root "$TMP/loc" set zh_CN >/dev/null 2>&1
grep -q "LANG=zh_CN.UTF-8" "$TMP/loc/etc/locale.conf" \
  && ok "写入了 locale.conf" || bad "未写入 locale.conf"
grep -q "zh_CN.UTF-8 UTF-8" "$TMP/loc/etc/locale.gen" \
  && ok "同时生成了 locale.gen（不会配了没生成）" || bad "未生成 locale.gen"
grep -q "KEYMAP=" "$TMP/loc/etc/vconsole.conf" \
  && ok "键盘布局单独设置（不与语言绑死）" || bad "未设键盘布局"
./bin/qylocale --root "$TMP/loc" check >/dev/null 2>&1 \
  && ok "设置后无问题" || bad "设置后仍报问题"

step "11. locale：C locale 会被拦下"
python3 -c "
import pathlib
pathlib.Path('$TMP/loc/etc/locale.conf').write_text('LANG=C\n')
"
./bin/qylocale --root "$TMP/loc" check > "$TMP/loc1.txt" 2>&1
grep -q "按字节处理" "$TMP/loc1.txt" \
  && ok "C locale 被拦下并说明后果" || bad "未拦下 C locale"

step "12. locale：设了但没生成要能检出（最难排查的一类）"
./bin/qylocale --root "$TMP/loc" set zh_CN >/dev/null 2>&1
python3 -c "
import pathlib
# 模拟：配了 LANG 但 locale.gen 里没有它
pathlib.Path('$TMP/loc/etc/locale.gen').write_text('C.UTF-8 UTF-8\n')
"
./bin/qylocale --root "$TMP/loc" check > "$TMP/loc2.txt" 2>&1
grep -q "静默回退" "$TMP/loc2.txt" \
  && ok "检出「配了但没生成」并说明会静默回退" || bad "未检出这类问题"

step "13. locale：不支持的语言要报错并给出可选"
./bin/qylocale --root "$TMP/loc" set xx_YY > "$TMP/loc3.txt" 2>&1
grep -q "不支持的语言" "$TMP/loc3.txt" \
  && grep -q "可选" "$TMP/loc3.txt" \
  && ok "不支持的语言报错并列出可选" || bad "未给出可选"
./bin/qylocale --root "$TMP/loc" set zh_TW --keymap us >/dev/null 2>&1 \
  && ok "中文可配美式键盘（外接键盘场景）" || bad "语言与键盘被绑死"

step "14. 清理"
qyrm "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
