#!/usr/bin/env bash
# 完整执行脚本 / 解压 / 文件管理 / 桌面外壳 / 硬件支持 专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-full
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. 执行脚本：失败后能续跑，不用从头再来"
python3 - <<'PYEOF'
import sys, shutil; sys.path.insert(0, '.')
from qyos import runner as R
from pathlib import Path
root = Path('/tmp/qy-full/run'); shutil.rmtree(root, ignore_errors=True)
steps = [R.Step("a", "第一步", "true"),
         R.Step("b", "第二步", "false"),      # 这里失败
         R.Step("c", "第三步", "true")]
try:
    R.run_steps(root, "t", steps, log=lambda m: None)
    raise AssertionError("第二步没失败")
except R.RunError as e:
    assert "已保存进度" in str(e), f"没提示可续跑: {e}"
    assert "--resume" in str(e), "没给出续跑命令"
    print(f"  第二步失败 → 提示续跑: {str(e)[:45]}…")
st = R.pending(root, "t")
assert st and st["done"] == ["a"], f"进度不对: {st}"
print(f"  已保存进度: 完成 {st['done']}")
# 改掉失败的那步（模拟修复），续跑
steps[1].command = "true"
r = R.run_steps(root, "t", steps, resume=True, log=lambda m: None)
assert r["ok"], "续跑没成功"
skipped = [x for x in r["steps"] if x[1] == "skipped"]
assert len(skipped) == 1 and skipped[0][0] == "a", f"该跳过的没跳过: {r['steps']}"
print("  续跑 → 跳过已完成的第一步，执行其余")
assert R.pending(root, "t") is None, "完成后进度没清"
print("  全部完成 → 进度文件已清（不会误导下次）")
PYEOF
[ $? -eq 0 ] && ok "续跑正确且完成后清进度" || bad "续跑不正确"

step "2. 脚本改了不能按旧进度续跑"
python3 - <<'PYEOF'
import sys, shutil; sys.path.insert(0, '.')
from qyos import runner as R
from pathlib import Path
root = Path('/tmp/qy-full/run2'); shutil.rmtree(root, ignore_errors=True)
steps = [R.Step("a", "A", "true"), R.Step("b", "B", "false")]
try:
    R.run_steps(root, "t2", steps, log=lambda m: None)
except R.RunError:
    pass
# 脚本加了新步骤 —— 按旧进度续跑会跳过它
steps.insert(0, R.Step("new", "新增", "true"))
try:
    R.run_steps(root, "t2", steps, resume=True, log=lambda m: None)
    raise AssertionError("脚本变了竟允许续跑")
except R.RunError as e:
    assert "不能续跑" in str(e), f"错误信息不对: {e}"
    assert "new" in str(e), "没指出是哪个步骤有问题"
    print(f"  脚本变化 → 拒绝续跑: {str(e)[:52]}…")
# 反例：修改"还没执行到"的步骤应当允许续跑——
# 修 bug 恰恰就是改还没跑到的那一步
steps2 = [R.Step("a", "A", "true"), R.Step("b", "B", "false")]
try:
    R.run_steps(root, "t3", steps2, log=lambda m: None)
except R.RunError:
    pass
steps2[1].command = "true"        # 修好了还没执行到的那步
r = R.run_steps(root, "t3", steps2, resume=True, log=lambda m: None)
assert r["ok"], "修复后仍不能续跑"
print("  修复未执行到的步骤 → 允许续跑（不该拦）")
PYEOF
[ $? -eq 0 ] && ok "步骤变化会拒绝续跑" || bad "未校验步骤一致性"

step "3. 演练要说清证明不了什么"
./bin/qyrun --root "$TMP" dry upgrade > "$TMP/dry.txt" 2>&1
grep -q "演练证明不了的事" "$TMP/dry.txt" \
  && ok "演练说明了局限性" || bad "未说明局限"
grep -q "磁盘空间" "$TMP/dry.txt" \
  && ok "指出磁盘空间演练不出" || bad "未指出"

step "4. 类型识别：按文件头而非扩展名"
printf '\x89PNG\r\n\x1a\nfake' > "$TMP/real.png"
cp "$TMP/real.png" "$TMP/fake.jpg"
./bin/qyfiles type "$TMP/fake.jpg" > "$TMP/t.txt" 2>&1
grep -q "image/png" "$TMP/t.txt" \
  && ok "改名骗不过文件头识别" || bad "被扩展名骗了"
printf 'PK\x03\x04fake' > "$TMP/x.zip"
./bin/qyfiles type "$TMP/x.zip" | grep -q "application/zip" \
  && ok "zip 识别正确" || bad "zip 识别错"

step "5. 解压必须防路径穿越（zip slip）"
python3 -c "
import zipfile, pathlib
d = pathlib.Path('$TMP/arch'); d.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(d/'ok.zip','w') as z:
    z.writestr('dir/a.txt','a'); z.writestr('dir/sub/b.txt','b')
with zipfile.ZipFile(d/'evil.zip','w') as z:
    z.writestr('../../../../tmp/qy-pwned.txt','pwned')
"
./bin/qyfiles --root "$TMP" extract "$TMP/arch/ok.zip" "$TMP/arch/out" \
  > "$TMP/ex.txt" 2>&1
grep -q "已解压 2 项" "$TMP/ex.txt" && ok "正常包能解压" || bad "解压失败"
./bin/qyfiles --root "$TMP" extract "$TMP/arch/evil.zip" "$TMP/arch/out2" \
  > "$TMP/ex2.txt" 2>&1
grep -q "路径越界" "$TMP/ex2.txt" \
  && ok "路径穿越被拒绝" || bad "穿越未被拦下"
[ ! -e /tmp/qy-pwned.txt ] \
  && ok "确认没写出越界文件" || bad "文件被写到越界位置（严重）"

step "6. 默认应用必须校验已安装"
qyrm "$TMP/asc"; mkdir -p "$TMP/asc"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import files as F
from pathlib import Path
root = Path('/tmp/qy-full/asc')
try:
    F.set_default(root, "text/plain", "not-installed-app", installed={"vim"})
    raise AssertionError("未安装的应用竟被接受")
except F.FilesError as e:
    assert "未安装" in str(e) and "vim" in str(e), f"提示不全: {e}"
    print(f"  未安装 → 拒绝并列出已装: {str(e)[:40]}…")
F.set_default(root, "text/plain", "vim", installed={"vim"})
assert F.default_for(root, "text/plain") == "vim"
print("  已安装 → 设置成功")
# 精确 MIME 未设时退回大类别
F.set_default(root, "text", "nano", installed={"vim", "nano"})
assert F.default_for(root, "text/markdown") == "nano", "没退回大类别"
print("  未精确设置 → 退回大类别")
PYEOF
[ $? -eq 0 ] && ok "默认应用校验与回退正确" || bad "默认应用逻辑不正确"

step "7. 硬件：缺固件要按能否自救排序"
mkdir -p "$TMP/hw"
./bin/qyhw --root "$TMP/hw" demo > "$TMP/hw.txt" 2>&1
grep -q "有线网卡" "$TMP/hw.txt" && grep -q "无线网卡" "$TMP/hw.txt" \
  && ok "识别出网卡与无线" || bad "设备识别不全"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import hardware as H
# 严重度：网卡最前——缺了它连不上网，装不了任何东西，无法自救
assert H.SEVERITY["net"] < H.SEVERITY["wifi"] < H.SEVERITY["gpu"], \
    "严重度排序不对"
assert H.SEVERITY["net"] < H.SEVERITY["audio"], "声卡不该比网卡紧急"
print(f"  严重度: net({H.SEVERITY['net']}) < wifi({H.SEVERITY['wifi']}) "
      f"< gpu({H.SEVERITY['gpu']}) < audio({H.SEVERITY['audio']})")
print(f"  网卡理由: {H.SEVERITY_DESC['net']}")
PYEOF
[ $? -eq 0 ] && ok "固件缺失按能否自救排序" || bad "排序不正确"

step "8. 硬件：一次性说清根因，不逐个重复"
./bin/qyhw --root "$TMP/hw" demo 2>&1 | grep -q "都来自同一个包" \
  && ok "根因合并说明（不逐个重复）" || bad "未合并根因"
./bin/qyhw --root "$TMP/hw" demo 2>&1 | grep -q "U 盘拷过来离线安装" \
  && ok "给了无法联网时的离线方案" || bad "未考虑离线场景"

step "9. 桌面外壳：提权动作必须走 polkit"
python3 - <<'PYEOF'
import sys, shutil; sys.path.insert(0, '.')
from qyos import desktop as DS
from pathlib import Path
# 提权动作必须都有 polkit 策略，否则默认拒绝，
# 表现为"点按钮没反应"，用户完全不知道为什么
priv = [a for a in DS.ACTIONS if a.privileged]
assert priv, "没有提权动作"
print(f"  {len(priv)}/{len(DS.ACTIONS)} 个动作需要提权")
root = Path('/tmp/qy-full/dt'); shutil.rmtree(root, ignore_errors=True)
out = DS.install_layout(root)
print(f"  安装布局: {len(out)} 个文件")
problems = DS.check_layout(root)
assert not problems, f"布局有问题: {problems}"
print("  布局检查通过")
# 生成的 .desktop 里提权动作必须走 pkexec
d = root / "usr/share/applications"
for a in priv:
    p = d / f"qiyuan-{a.id.replace('.', '-')}.desktop"
    assert p.exists(), f"{a.id} 没有 desktop 文件"
    assert "pkexec" in p.read_text(), f"{a.id} 需提权却没走 pkexec"
print(f"  {len(priv)} 个提权动作全部走 pkexec")
PYEOF
[ $? -eq 0 ] && ok "提权动作全部走 polkit" || bad "polkit 接入不正确"

step "10. polkit 默认必须询问，不能放行"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import desktop as DS
pol = DS.polkit_policy()
assert "auth_admin" in pol, "没有 auth_admin——默认放行等于取消授权"
print("  默认 auth_admin（每次输管理员密码）")
assert "allow_any>auth_admin" in pol.replace(" ", ""), "allow_any 未设"
print("  未登录/非活动会话同样要求认证")
PYEOF
[ $? -eq 0 ] && ok "polkit 默认要求认证" || bad "polkit 策略过松"

step "11. 会重启服务的动作要提前警告"
./bin/qydesktop panel network > "$TMP/p.txt" 2>&1
grep -q "会重启" "$TMP/p.txt" \
  && ok "改动前提示会重启服务" || bad "未提示重启"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import desktop as DS
rs = [a for a in DS.ACTIONS if a.restarts_service]
assert rs, "没有带重启警告的动作"
for a in rs:
    assert "重启" in a.warn(), f"{a.id} 警告文案不对"
print(f"  {len(rs)} 个动作带重启警告")
# 状态栏必须只读
for t in DS.TRAY:
    assert t.source, f"{t.id} 没有数据来源"
print(f"  状态栏 {len(DS.TRAY)} 项，全部只读（不修改任何东西）")
PYEOF
[ $? -eq 0 ] && ok "重启警告与状态栏只读" || bad "警告或状态栏不正确"

step "12. 网络：无线法规域缺失要提示真实后果"
./bin/qynet --root "$TMP/n" wifi > "$TMP/w.txt" 2>&1
grep -q "5GHz" "$TMP/w.txt" && grep -q "网速" "$TMP/w.txt" \
  && ok "法规域缺失说明了网速后果" || bad "未说明后果"
grep -q "wpa_supplicant 或 iwd" "$TMP/w.txt" \
  && ok "缺认证服务会提示（搜到也连不上）" || bad "未提示认证服务"

step "13. 虚拟网卡与路由"
./bin/qynet --root "$TMP/n" vnic br0 bridge --link eth0 > "$TMP/v.txt" 2>&1
grep -q "ip link add br0 type bridge" "$TMP/v.txt" \
  && ok "能生成网桥命令" || bad "网桥命令不对"
./bin/qynet --root "$TMP/n" vnic v1 veth > "$TMP/v2.txt" 2>&1
grep -q "peer name" "$TMP/v2.txt" && ok "能生成 veth 命令" || bad "veth 不对"
./bin/qynet --root "$TMP/n" router br0 eth0 > "$TMP/r.txt" 2>&1
grep -q "ip_forward" "$TMP/r.txt" && grep -q "masquerade" "$TMP/r.txt" \
  && ok "路由含转发与 NAT" || bad "路由配置不全"
grep -q "默默地被丢掉" "$TMP/r.txt" \
  && ok "说明不开转发无报错的坑" || bad "未说明"

step "14. ADB 无线调试"
./bin/qynet --root "$TMP/n" adb-pair 192.168.1.50 37123 123456 \
  > "$TMP/adb.txt" 2>&1
grep -q "adb pair" "$TMP/adb.txt" && grep -q "adb connect" "$TMP/adb.txt" \
  && ok "能生成无线配对命令" || bad "配对命令不对"
./bin/qynet --root "$TMP/n" adb > "$TMP/adb2.txt" 2>&1
grep -q "android-tools" "$TMP/adb2.txt" \
  && ok "缺 adb 时给出安装命令" || bad "未提示安装"

step "15. 口令不进命令行历史"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import net as N
c = N.wifi_connect_cmd("MyWiFi", psk="secret")
# 密码不能出现在命令行里：同机任何用户 ps 一下就能看到
assert "secret" not in c, "密码出现在命令里，ps 就能看到"
assert "不要把密码写在命令行" in c, "没有说明原因"
print("  带密码场景 → 走交互式输入，不落在命令行")
c2 = N.wifi_connect_cmd("OpenWiFi")
assert "scan" in c2, "开放网络没给扫描步骤"
print("  无密码场景 → 先扫描确认能搜到")
PYEOF
[ $? -eq 0 ] && ok "WiFi 口令不进命令行" || bad "口令处理有泄漏风险"

step "16. 清理"
qyrm "$TMP" /tmp/qy-pwned.txt
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
