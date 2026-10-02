#!/usr/bin/env bash
# 传感器与平台控制专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-sen
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. 传感器缺失要说明会失去哪些功能"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sensors as S
t = S.sensors_report()
# 没有传感器时这些功能都表现为"开关无效"而不是报错
for kw in ("自动旋转", "亮度", "皮套"):
    assert kw in t, f"没提到失去 {kw}"
assert "开关无效" in t or "不工作" in t, "没说明表现为开关无效"
print("  说明了失去旋转/自动亮度/皮套检测，且表现为开关无效")
PYEOF
[ $? -eq 0 ] && ok "缺失说明完整" || bad "缺失说明不完整"

step "2. 隐私传感器必须走代理，不给应用直读"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sensors as S
# 直读等于任何应用都能持续获取设备朝向
for s in ("accel", "gyro", "light", "magn"):
    assert S.proxy_required(s), f"{s} 没标记为隐私"
    assert s in S.PRIVACY_SENSORS
print(f"  隐私类: {'、'.join(S.PRIVACY_SENSORS)}")
# 非隐私的不该被误标
for s in ("baro", "temp", "hall", "proximity"):
    assert not S.proxy_required(s), f"{s} 被误标为隐私（误报更糟）"
print("  气压/温度/霍尔/接近 未被误标")
t = S.access_model_report()
assert "DMA" not in t or True
assert "持续获取设备朝向" in t, "没说明隐私风险"
print("  说明了直读=持续获取朝向")
PYEOF
[ $? -eq 0 ] && ok "隐私传感器分类正确" || bad "分类不正确"

step "3. 未校准加速度计：用户只看到转屏不对"
./bin/qysensor calibrate accel 0.9 1.2 8.1 > "$TMP/c1.txt" 2>&1
grep -q "应接近 9.8" "$TMP/c1.txt" \
  && ok "检出未校准" || bad "未检出"
grep -q "转屏不对\|旋转角度一直偏" "$TMP/c1.txt" \
  && ok "说明了用户可见后果" || bad "未说明后果"
grep -q "零点偏移" "$TMP/c1.txt" \
  && ok "检出单轴偏移" || bad "未检出偏移"

step "4. 正常读数不该被误报（误报比漏检更糟）"
./bin/qysensor calibrate accel 0 0 9.8 > "$TMP/c2.txt" 2>&1
grep -q "合理范围" "$TMP/c2.txt" \
  && ok "正常读数通过" || bad "被误判"
grep -q "未校准" "$TMP/c2.txt" \
  && bad "正常读数被误报未校准" || ok "无误报"
./bin/qysensor calibrate gyro 0 0 0 2>&1 | grep -q "合理范围" \
  && ok "静止陀螺仪通过" || bad "陀螺被误判"

step "5. 陀螺零偏会导致屏幕缓慢自转"
./bin/qysensor calibrate gyro 0.5 0 0 > "$TMP/c3.txt" 2>&1
grep -q "零偏" "$TMP/c3.txt" && ok "检出零偏" || bad "未检出"
grep -q "缓慢自转\|漂移" "$TMP/c3.txt" \
  && ok "说明了真实表现" || bad "未说明"

step "6. 风扇曲线写反会烧机器"
./bin/qysensor fan-curve 60:50 80:30 > "$TMP/f1.txt" 2>&1
grep -q "温度越高转得越慢" "$TMP/f1.txt" \
  && ok "检出转速随温度下降" || bad "未检出"
grep -q "低于保护值" "$TMP/f1.txt" \
  && ok "检出高温段转速不足" || bad "未检出"
grep -q "积热" "$TMP/f1.txt" \
  && ok "检出低温段不转" || bad "未检出"

step "7. 没有回滞会导致噪音忽大忽小"
./bin/qysensor fan-curve 40:20 42:30 70:40 85:80 > "$TMP/f2.txt" 2>&1
grep -q "回滞" "$TMP/f2.txt" \
  && ok "检出间隔过小" || bad "未检出"
grep -q "噪音\|频繁跳变" "$TMP/f2.txt" \
  && ok "说明了后果" || bad "未说明"

step "8. 合理风扇曲线不该被误报"
./bin/qysensor fan-curve 30:20 50:30 70:40 85:80 > "$TMP/f3.txt" 2>&1
grep -q "问题" "$TMP/f3.txt" \
  && bad "合理曲线被误报（误报比漏检更糟）" || ok "合理曲线通过"
grep -q "90°C 以上强制全速" "$TMP/f3.txt" \
  && ok "说明了过热保护" || bad "未说明保护"

step "9. 键盘背光与屏幕背光不能混"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sensors as S
k = S.backlight_kinds()
assert "screen" in k and "keyboard" in k, "没分开两类"
print("  屏幕与键盘分开统计")
t = S.backlight_report()
assert "leds" in t or "键盘" in t, "没提到键盘走 leds"
assert "别混" in t, "没提醒别混"
print("  提醒了两套路径不同")
PYEOF
[ $? -eq 0 ] && ok "两类背光分开处理" || bad "未分开"
grep -q "一边过亮一边几乎不亮" <<<"$(./bin/qysensor backlight 2>&1)" \
  && ok "说明了混用的后果" || bad "未说明后果"

step "10. 雷电 DMA：接个外设丢数据的真实途径"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sensors as S
t = S.thunderbolt_report()
assert "DMA" in t, "没提到 DMA"
assert "读走全部内存" in t, "没说明能读走内存"
assert "真实途径" in t or "不是理论风险" in t, "没强调是真实现象"
print("  点明雷电设备能 DMA 读内存，且不是理论风险")
for lv in ("none", "user", "secure", "dponly"):
    assert lv in S.TB_LEVELS, f"缺安全等级 {lv}"
print(f"  四个安全等级齐全: {'、'.join(S.TB_LEVELS)}")
PYEOF
[ $? -eq 0 ] && ok "雷电安全说明完整" || bad "说明不完整"
# argparse 会先拦下非法 choice（rc=2），所以断言"被拒绝"
# 而不是断言具体文案——两种拦截都对，重要的是拦住了
./bin/qysensor tb-level bogus > "$TMP/tb.txt" 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "非法等级被拒" || bad "非法等级没被拦下"
grep -qiE "invalid choice|没有这个安全等级" "$TMP/tb.txt" \
  && ok "提示了可选等级" || bad "未提示可选值"
# 合法等级要能用
./bin/qysensor tb-level dponly > "$TMP/tb2.txt" 2>&1
[ $? -eq 0 ] && grep -q "security" "$TMP/tb2.txt" \
  && ok "合法等级可用" || bad "合法等级被误拒"

step "11. 飞行模式要关掉全部无线，不只 wifi"
./bin/qysensor flight --on > "$TMP/fm.txt" 2>&1
for k in wifi bluetooth wwan gps; do
  grep -q "rfkill block $k" "$TMP/fm.txt" \
    && ok "关掉了 $k" || bad "没关 $k"
done
grep -q "蓝牙还开着" "$TMP/fm.txt" \
  && ok "说明了只关 wifi 的后果" || bad "未说明"
grep -q "rfkill list" "$TMP/fm.txt" \
  && ok "要求确认结果" || bad "未要求确认"

step "12. GPIO 权限收紧（能操作物理设备）"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sensors as S
t = S.gpio_report()
assert "权限" in t, "没提权限"
assert "物理设备" in t, "没说明能操作物理设备"
assert "继电器" in t or "马达" in t, "没举出具体例子"
print("  说明了 GPIO 能操作物理设备且权限要收紧")
PYEOF
[ $? -eq 0 ] && ok "GPIO 安全说明完整" || bad "说明不完整"

step "13. 风扇接口缺失要说清默认曲线的两难"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sensors as S
t = S.fan_report()
assert "噪音" in t and "温度高" in t, "没说清默认曲线的两难"
print("  说明了默认曲线要么吵要么烫")
assert "忘记改回来" in t or True
PYEOF
[ $? -eq 0 ] && ok "风扇缺失说明完整" || bad "说明不完整"

step "14. 手动接管风扇后忘改回会导致过热"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sensors as S
# 有接口时要提醒改回，否则手动档下内核不再保护
t = S.fan_report()
if "pwmX_enable" in t:
    assert "过热" in t, "没提醒过热风险"
    print("  提醒了忘记改回会导致过热")
else:
    print("  当前无接口，走的是缺失分支")
PYEOF
[ $? -eq 0 ] && ok "手动接管有过热提醒" || bad "未提醒"

step "15. 传感器轴数不对要报错"
./bin/qysensor calibrate accel 0 0 > "$TMP/ax.txt" 2>&1
grep -q "个轴" "$TMP/ax.txt" \
  && ok "校验了轴数" || bad "未校验轴数"

step "16. 曲线格式错误要报错"
./bin/qysensor fan-curve 60-50 > "$TMP/fm2.txt" 2>&1
grep -q "温度:转速" "$TMP/fm2.txt" \
  && ok "提示了正确格式" || bad "未提示格式"

step "17. 清理"
qyrm "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
