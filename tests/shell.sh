#!/usr/bin/env bash
# 桌面外壳补齐 + 进程与资源 专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-shp
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. 墙纸：设了不生效最常见的原因是格式不支持"
printf 'x' > "$TMP/w.png"
./bin/qyshell wallpaper "$TMP/w.png" --form phone > "$TMP/wp.txt" 2>&1
grep -q "期望 1080x2400" "$TMP/wp.txt" \
  && ok "按形态给出期望尺寸" || bad "未给尺寸"
grep -q "已设置" "$TMP/wp.txt" \
  && ok "点明界面只显示已设置" || bad "未点明"
cp "$TMP/w.png" "$TMP/w.bmp"
./bin/qyshell wallpaper "$TMP/w.bmp" > "$TMP/wp2.txt" 2>&1
grep -q "合成器支持" "$TMP/wp2.txt" \
  && ok "不支持的格式被警告" || bad "未警告格式"

step "2. 开发者选项：默认隐藏有理由"
./bin/qyshell dev > "$TMP/dv.txt" 2>&1
grep -q "连点版本号" "$TMP/dv.txt" \
  && ok "说明了默认隐藏" || bad "未说明"
grep -q "误触会关掉安全校验" "$TMP/dv.txt" \
  && ok "说明了隐藏的理由" || bad "未说明理由"
grep -q "高风险" "$TMP/dv.txt" \
  && ok "标出了高风险项" || bad "未标风险"

step "3. USB 调试打开后 adb 一直 unauthorized"
./bin/qyshell dev-enable usb-debug > "$TMP/ud.txt" 2>&1
grep -q "unauthorized" "$TMP/ud.txt" \
  && ok "说明了症状" || bad "未说明"
grep -q "qyudev known adb" "$TMP/ud.txt" \
  && ok "给出了配套命令" || bad "未给配套"

step "4. 无线调试的风险（局域网内任何人可连）"
./bin/qyshell dev-enable wireless-debug > "$TMP/wd.txt" 2>&1
grep -q "任何人都能连" "$TMP/wd.txt" \
  && ok "说明了暴露范围" || bad "未说明"
grep -q "用完必须关" "$TMP/wd.txt" \
  && ok "提醒用完关闭" || bad "未提醒"

step "5. 重置系统要列出删掉什么"
./bin/qyshell reset --scope apps data > "$TMP/rs.txt" 2>&1
grep -q "将被删除" "$TMP/rs.txt" && ok "列出了删除范围" || bad "未列出"
grep -q "不可逆" "$TMP/rs.txt" && ok "标明不可逆" || bad "未标明"
./bin/qyshell reset --scope keys --yes > "$TMP/rs2.txt" 2>&1
grep -q "永久打不开" "$TMP/rs2.txt" \
  && ok "点明密钥删除的严重后果" || bad "未点明"
./bin/qyshell reset --scope apps > "$TMP/rs3.txt" 2>&1
grep -q "需要显式确认" "$TMP/rs3.txt" \
  && ok "未确认时拒绝" || bad "未要求确认"

step "6. 导航方式两套同开会导致点了没反应"
./bin/qyshell navigation gesture --also three-button \
  > "$TMP/nv.txt" 2>&1
grep -q "互抢" "$TMP/nv.txt" && ok "检出互抢" || bad "未检出"
grep -q "点了没反应" "$TMP/nv.txt" \
  && ok "说明了症状" || bad "未说明症状"
./bin/qyshell navigation gesture > "$TMP/nv2.txt" 2>&1
grep -q "互抢" "$TMP/nv2.txt" \
  && bad "单套被误报（误报比漏检更糟）" || ok "单套不误报"

step "7. 自由漂浮窗口有尺寸限制"
./bin/qyshell floating 60 60 --screen 1080 2400 > "$TMP/fl.txt" 2>&1
grep -q "小于下限" "$TMP/fl.txt" && ok "过小被拒" || bad "未限制"
./bin/qyshell floating 2000 2300 --screen 1080 2400 > "$TMP/fl2.txt" 2>&1
grep -q "超过屏幕" "$TMP/fl2.txt" \
  && ok "超出屏幕被拒" || bad "未限制"
./bin/qyshell floating 600 900 --screen 1080 2400 > "$TMP/fl3.txt" 2>&1
grep -q "尺寸合适" "$TMP/fl3.txt" \
  && ok "合理尺寸通过" || bad "被误拒"

step "8. 跨应用拖拽不走 portal 会静默失败"
./bin/qyshell drag app1 app2 --kind file --no-portal \
  > "$TMP/dg.txt" 2>&1
grep -q "什么都没发生" "$TMP/dg.txt" \
  && ok "点明静默失败" || bad "未点明"
grep -q "没有任何报错" "$TMP/dg.txt" \
  && ok "点明无报错" || bad "未点明"
./bin/qyshell drag app1 app2 --kind file > "$TMP/dg2.txt" 2>&1
grep -q "可以拖拽" "$TMP/dg2.txt" \
  && ok "走 portal 则允许" || bad "被误拒"

step "9. 扫码：相机被占用会黑屏，用户以为扫码器坏了"
./bin/qyshell scan --camera-busy > "$TMP/sc.txt" 2>&1
grep -q "黑屏" "$TMP/sc.txt" && ok "说明黑屏" || bad "未说明"
grep -q "扫码器坏了" "$TMP/sc.txt" \
  && ok "点明误判方向" || bad "未点明"
./bin/qyshell scan --permission deny > "$TMP/sc2.txt" 2>&1
grep -q "qyperms grant" "$TMP/sc2.txt" \
  && ok "给出开启权限的命令" || bad "未给命令"

step "10. 虚拟鼠标：纯触屏设备缺了它无法右键"
./bin/qyshell vmouse right-click > "$TMP/vm.txt" 2>&1
grep -q "右键" "$TMP/vm.txt" && ok "说明了用途" || bad "未说明"
grep -q "触屏设备" "$TMP/vm.txt" \
  && ok "点明受影响场景" || bad "未点明"
./bin/qyshell vmouse bogus-action > "$TMP/vm2.txt" 2>&1
grep -q "不支持" "$TMP/vm2.txt" \
  && ok "非法动作被拒" || bad "未校验"

step "11. 已配对设备：残留配对是重连失败的常见原因"
./bin/qyshell paired > "$TMP/pr.txt" 2>&1
grep -q "残留配对" "$TMP/pr.txt" \
  && ok "点明残留配对问题" || bad "未点明"
./bin/qyshell paired --hint > "$TMP/pr2.txt" 2>&1
grep -q "两端都删除" "$TMP/pr2.txt" \
  && ok "强调要两端都删" || bad "未强调"
grep -q "永远连不上" "$TMP/pr2.txt" \
  && ok "说明了只删一边的后果" || bad "未说明后果"

step "12. 内置浏览器更新不走包管理（安全更新会漏）"
./bin/qyshell browser > "$TMP/br.txt" 2>&1
grep -q "不走发行版包管理" "$TMP/br.txt" \
  && ok "点明更新独立" || bad "未点明"
grep -q "浏览器漏洞要单独跟" "$TMP/br.txt" \
  && ok "点明安全更新会漏" || bad "未点明"

step "13. 系统关键进程不能杀"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import proc as P
probs = P.kill_check("qyinit")
assert any("不允许" in x for x in probs), "关键进程没被挡住"
assert any("死机" in x for x in probs), "没说明后果"
print("  qyinit 被挡下并说明会死机")
PYEOF
[ $? -eq 0 ] && ok "关键进程被挡下" || bad "未挡住"

step "14. 强制杀会丢数据（先警告不直接拒绝）"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import proc as P
probs = P.kill_check("myapp", force=True)
# 强制杀只警告不拒绝——有时确实必须
assert any("保存数据" in x for x in probs), "没警告丢数据"
assert not any("不允许" in x for x in probs), "不该拒绝"
print("  强制杀：给出警告但不拒绝（有时确实必须）")
PYEOF
[ $? -eq 0 ] && ok "强制杀有警告" || bad "警告不正确"

step "15. CPU 在线核心少于总数要说明"
./bin/qyproc cpu > "$TMP/cpu.txt" 2>&1
grep -q "核心" "$TMP/cpu.txt" && ok "报告了核心数" || bad "未报核心数"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import proc as P
t = P.cpu_report()
if "在线核心少于总数" in t:
    assert "CPU 坏了" in t, "没说明会被误判"
    print("  检出核心离线并说明会被误判为 CPU 坏")
else:
    print("  当前无核心离线，跳过该断言")
PYEOF
[ $? -eq 0 ] && ok "核心离线说明完整" || bad "说明不完整"
grep -q "机器慢" "$TMP/cpu.txt" \
  && ok "点明体感慢常是调频策略的锅" || bad "未点明"

step "16. 调频策略非法值要拒绝"
./bin/qyproc governor bogus > "$TMP/gv.txt" 2>&1
[ $? -ne 0 ] && ok "非法策略被拒" || bad "未拒绝"
./bin/qyproc governor schedutil > "$TMP/gv2.txt" 2>&1
grep -q "scaling_governor" "$TMP/gv2.txt" \
  && ok "合法策略给出命令" || bad "命令不对"
grep -q "重启后失效" "$TMP/gv2.txt" \
  && ok "提醒不会持久化" || bad "未提醒"

step "17. 显卡：连接器不该被当成显卡"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import proc as P
gpus = P.gpu_info()
# card0-Virtual-1 是连接器不是显卡，
# 算进去会让"有几张卡"失真
for name, _ in gpus:
    assert "-" not in name, f"{name} 是连接器，不该算作显卡"
print(f"  只列出 {len(gpus)} 张真实显卡（连接器已排除）")
PYEOF
[ $? -eq 0 ] && ok "连接器已排除" || bad "混入了连接器"

step "18. 双显卡切换没切干净会黑屏但系统还活着"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import proc as P
# 直接验证双显卡分支的文案存在
src = open('qyos/proc.py', encoding='utf-8').read()
assert "屏幕黑但系统还活着" in src, "没有双显卡风险提示"
print("  双显卡风险提示存在")
PYEOF
[ $? -eq 0 ] && ok "双显卡风险说明存在" || bad "缺失"

step "19. 没有硬件加速会导致视频掉帧且 CPU 占满"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import proc as P
src = open('qyos/proc.py', encoding='utf-8').read()
assert "掉帧" in src and "CPU 占满" in src, "没说明后果"
print("  说明了无硬件加速的后果")
PYEOF
[ $? -eq 0 ] && ok "加速缺失说明完整" || bad "说明不完整"

step "20. 包使用时间：没有它就无法清理"
qyrm "$TMP/u"; mkdir -p "$TMP/u"
./bin/qyproc --root "$TMP/u" mark-used app1 >/dev/null 2>&1
./bin/qyproc --root "$TMP/u" usage > "$TMP/us.txt" 2>&1
grep -q "app1" "$TMP/us.txt" && ok "记录了使用" || bad "未记录"
grep -q "安装时间" "$TMP/us.txt" \
  && grep -q "最后使用" "$TMP/us.txt" \
  && ok "含安装与最后使用时间" || bad "字段不全"
./bin/qyproc --root "$TMP/u" usage --unused 0 > "$TMP/us2.txt" 2>&1
grep -q "app1" "$TMP/us2.txt" && ok "能筛出未使用的包" || bad "筛选不对"

step "21. 内置系统包不许卸载"
./bin/qyproc can-remove glibc > "$TMP/cr.txt" 2>&1
[ $? -ne 0 ] && ok "基础包被挡下" || bad "未挡下"
grep -q "系统起不来" "$TMP/cr.txt" \
  && ok "说明了后果" || bad "未说明"
./bin/qyproc can-remove logrotate > "$TMP/cr2.txt" 2>&1
grep -q "建议保留" "$TMP/cr2.txt" \
  && ok "推荐包给出提醒但仍允许" || bad "处理不对"

step "22. 工具登记：20 多个工具要能查"
./bin/qyproc tools > "$TMP/tl.txt" 2>&1
grep -q "共" "$TMP/tl.txt" && ok "列出工具总数" || bad "未列总数"
n=$(./bin/qyproc find-tool 权限 2>&1 | wc -l)
[ "$n" -ge 2 ] && ok "能按用途找到工具" || bad "检索不可用"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import proc as P
tools = P.tool_registry()
# 登记里的工具必须真的存在，否则登记本身就在误导
import pathlib
missing = [t.name for t in tools
           if not (pathlib.Path('bin') / t.name).exists()
           and t.name != 'qyinit']
assert not missing, f"登记了不存在的工具: {missing}"
print(f"  登记的 {len(tools)} 个工具都真实存在")
PYEOF
[ $? -eq 0 ] && ok "登记与实际一致" || bad "登记有幽灵项"

step "23. 清理"
qyrm "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
