#!/usr/bin/env bash
# 通用包（Flatpak/Snap/AppImage）与运行时专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-apptest
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. 危险权限要能识别"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import app as A
a = A.App(app_id="x", name="x", kind=A.FLATPAK,
          perms=[A.AppPerm("filesystem=home"),
                 A.AppPerm("network"),
                 A.AppPerm("camera")])
d = a.dangerous()
assert len(d) == 1 and d[0].name == "filesystem=home", f"高危识别错: {d}"
print("  filesystem=home → 高危（能读 SSH 私钥）")
r = a.needs_review()
names = {p.name for p in r}
assert "network" in names and "camera" in names, f"复核项识别错: {names}"
print("  network / camera → 值得复核")
# 未授予的权限不该算
a2 = A.App(app_id="y", name="y", kind=A.SNAP,
           perms=[A.AppPerm("filesystem=home", granted=False)])
assert not a2.dangerous(), "未授予的权限被算进高危"
print("  granted=False → 不计入（无误报）")
PYEOF
[ $? -eq 0 ] && ok "高危与复核权限识别正确" || bad "权限分级不正确"

step "2. AppImage 无校验和也无签名必须报"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import app as A
# AppImage 最大优点是不留残留，最大风险是没有来源验证——
# 一个没校验和也没签名的 AppImage 可以是任何人做的
bad_app = A.App(app_id="u", name="未知来源", kind=A.APPIMAGE)
probs = A.audit_apps([bad_app])
assert any("既无校验和也无签名" in p for p in probs), f"未报: {probs}"
print("  无校验和无签名 → 报错")
good = A.App(app_id="s", name="已校验", kind=A.APPIMAGE,
             sha256="a"*64)
assert not A.audit_apps([good]), "有校验和的被误报"
print("  有 sha256 → 不报（无误报）")
good2 = A.App(app_id="g", name="已签名", kind=A.APPIMAGE, signed=True)
assert not A.audit_apps([good2]), "已签名的被误报"
print("  已签名 → 不报（无误报）")
PYEOF
[ $? -eq 0 ] && ok "AppImage 来源校验且不误报" || bad "AppImage 校验不正确"

step "3. AppImage 检查：执行位与体积"
printf '\x7fELF fake' > "$TMP/a.AppImage"; chmod +x "$TMP/a.AppImage"
./bin/qyapp --root "$TMP" check-appimage "$TMP/a.AppImage" > "$TMP/ai.txt" 2>&1
grep -q "可执行: 是" "$TMP/ai.txt" && ok "有执行位 → 通过" || bad "执行位判断错"
grep -q "sha256:" "$TMP/ai.txt" && ok "给出了 sha256" || bad "未给校验和"
chmod -x "$TMP/a.AppImage"
./bin/qyapp --root "$TMP" check-appimage "$TMP/a.AppImage" > "$TMP/ai2.txt" 2>&1
grep -q "chmod +x" "$TMP/ai2.txt" \
  && ok "无执行位 → 提示 chmod +x" || bad "未提示加执行位"

step "4. AppImage 默认不留残留"
./bin/qyapp --root "$TMP" run "$TMP/a.AppImage" > "$TMP/run.txt" 2>&1
grep -q "extract" "$TMP/run.txt" \
  && bad "默认不该解压" || ok "默认直接执行（不留残留）"
./bin/qyapp --root "$TMP" run "$TMP/a.AppImage" --extract > "$TMP/run2.txt" 2>&1
grep -q "appimage-extract-and-run" "$TMP/run2.txt" \
  && grep -q "会解到临时目录" "$TMP/run2.txt" \
  && ok "兜底方式会说明要清理" || bad "兜底方式未说明副作用"

step "5. 沙箱策略只给申请过的权限"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import app as A
# 只申请 network
a = A.App(app_id="n", name="n", kind=A.FLATPAK, path="/bin/n",
          perms=[A.AppPerm("network")])
pol = A.sandbox_policy(a)
assert "--share-net" in pol, "申请的 network 没给"
print("  申请 network → 放行网络")
assert "--bind $HOME" not in pol, "没申请 home 却给了"
print("  未申请 home → 不放行家目录")
# 特权设备：申请了才给
a2 = A.App(app_id="c", name="c", kind=A.FLATPAK, path="/bin/c",
           perms=[A.AppPerm("camera")])
assert "/dev/video0" in A.sandbox_policy(a2), "申请的摄像头没给"
print("  申请 camera → 放行摄像头")
assert "/dev/video0" not in A.sandbox_policy(a), "没申请却给了摄像头"
print("  未申请 → 不放行（无误报）")
# 最小集必须一直在
assert "--ro-bind /usr /usr" in pol, "缺 /usr"
assert "--die-with-parent" in pol, "缺随父进程退出"
print("  最小集（/usr 只读、随父退出）始终存在")
PYEOF
[ $? -eq 0 ] && ok "沙箱按申请授权，不多给" || bad "沙箱策略不正确"

step "6. 运行时多版本共存与排序"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import app as A
from pathlib import Path
root = Path('/tmp/qy-apptest/rt')
import shutil; shutil.rmtree(root, ignore_errors=True)
rts = [A.Runtime("org.freedesktop.Platform", "22.08", "x86_64"),
       A.Runtime("org.freedesktop.Platform", "24.08", "x86_64"),
       A.Runtime("org.freedesktop.Platform", "23.08", "x86_64")]
A.save_runtimes(root, rts)
got = A.runtime_versions(A.load_runtimes(root), "org.freedesktop.Platform")
order = [r.version for r in got]
# 必须按数字比：'24.08' > '23.08'，字符串比较虽然这里也对，
# 但 '9.0' vs '10.0' 就会错
assert order == ["24.08", "23.08", "22.08"], f"排序错: {order}"
print(f"  三个版本排序: {order}")
# 关键：10.0 必须大于 9.0（字符串比较会得出相反结论）
rts2 = [A.Runtime("r", "9.0"), A.Runtime("r", "10.0")]
A.save_runtimes(root, rts2)
o2 = [r.version for r in A.runtime_versions(A.load_runtimes(root), "r")]
assert o2 == ["10.0", "9.0"], f"9.0/10.0 排序错: {o2}"
print("  10.0 > 9.0（按数字比，不是字符串比）")
PYEOF
[ $? -eq 0 ] && ok "运行时按版本号正确排序" || bad "运行时排序不正确"

step "7. 运行时被使用中不能删"
python3 - <<'PYEOF'
import sys, shutil; sys.path.insert(0, '.')
from qyos import app as A
from pathlib import Path
root = Path('/tmp/qy-apptest/rt2'); shutil.rmtree(root, ignore_errors=True)
# 直接删掉正在被使用的运行时，那些应用会立刻起不来，
# 而报错通常是"找不到运行时"，看不出是谁删的、为什么
A.save_runtimes(root, [A.Runtime("P", "23.08", used_by=["编辑器", "播放器"]),
                       A.Runtime("P", "24.08", used_by=[])])
probs = A.runtime_check_removal(root, "P", "23.08")
assert probs and "编辑器" in probs[0], f"未检出在用: {probs}"
print(f"  23.08 在用 → 拒绝删除: {probs[0][:40]}…")
assert not A.runtime_check_removal(root, "P", "24.08"), "无应用的被误拦"
print("  24.08 无人使用 → 可删（无误报）")
PYEOF
[ $? -eq 0 ] && ok "在用运行时受保护且不误拦" || bad "运行时删除校验不正确"

step "8. 通用包要纳入登记（安全扫描能看见）"
python3 - <<'PYEOF'
import sys, shutil; sys.path.insert(0, '.')
from qyos import app as A
from pathlib import Path
root = Path('/tmp/qy-apptest/reg'); shutil.rmtree(root, ignore_errors=True)
A.register_app(root, A.App(app_id="a", name="A", kind=A.SNAP, version="1"))
A.register_app(root, A.App(app_id="a", name="A2", kind=A.SNAP, version="2"))
apps = A.load_apps(root)
# 重复登记应覆盖而不是堆积，否则"装了什么"这个清单会失真
assert len(apps) == 1 and apps[0].version == "2", f"重复登记: {apps}"
print("  重复登记 → 覆盖（清单不失真）")
assert len(apps) == 1 and apps[0].name == "A2"
PYEOF
[ $? -eq 0 ] && ok "重复登记会覆盖而非堆积" || bad "登记逻辑不正确"

step "9. 审计能汇总全机通用包风险"
python3 - <<'PYEOF'
import sys, shutil; sys.path.insert(0, '.')
from qyos import app as A
from pathlib import Path
root = Path('/tmp/qy-apptest/aud'); shutil.rmtree(root, ignore_errors=True)
A.register_app(root, A.App(app_id="r", name="危险应用", kind=A.SNAP,
                           perms=[A.AppPerm("classic")]))
A.register_app(root, A.App(app_id="s", name="安全应用", kind=A.FLATPAK,
                           perms=[A.AppPerm("wayland")]))
probs = A.audit_apps(A.load_apps(root))
assert len(probs) == 1 and "危险应用" in probs[0], f"审计错: {probs}"
assert "不做任何隔离" in probs[0], f"未说明为什么危险: {probs[0]}"
print(f"  检出: {probs[0]}")
PYEOF
[ $? -eq 0 ] && ok "审计能定位风险并说明原因" || bad "审计不正确"

step "10. 清理"
qyrm "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
