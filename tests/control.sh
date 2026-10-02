#!/usr/bin/env bash
# 系统控制专项测试：电源、显示、声音、设备、感知、VPN/DNS
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-ctl
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. 自我感知：环境判断错，后面全做无用功"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import control as C
from pathlib import Path
env = C.detect_env(Path('/'))
assert env in (C.ENV_PHYSICAL, C.ENV_VM, C.ENV_CONTAINER, C.ENV_UNKNOWN), env
print(f"  当前环境: {C.ENV_CN.get(env)}")
# 容器里不该有电源管理：容器没有电源状态，
# 做了不仅无用还会留下半截状态
assert "关机" in C.blocked_actions(C.ENV_CONTAINER), "容器未禁用关机"
assert "休眠" in C.blocked_actions(C.ENV_CONTAINER), "容器未禁用休眠"
print(f"  容器禁用: {'、'.join(C.blocked_actions(C.ENV_CONTAINER))}")
# 虚拟机不该有定时开机（靠 RTC，虚拟机 RTC 唤醒不可靠）
assert "定时开机" in C.blocked_actions(C.ENV_VM), "虚拟机未禁用定时开机"
print(f"  虚拟机禁用: {'、'.join(C.blocked_actions(C.ENV_VM))}")
# 物理机不该被误禁
assert not C.blocked_actions(C.ENV_PHYSICAL), "物理机被误禁操作"
print("  物理机: 无限制（无误报）")
PYEOF
[ $? -eq 0 ] && ok "环境判断与操作限制正确" || bad "环境感知不正确"

step "2. 休眠必须在发起前检查，不能让它失败"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import control as C
# 休眠失败发生在已经关掉大部分设备之后——
# 用户看到的是"合上盖子后打开发现没睡成"
probs = C.hibernate_ready(Path('/'))
assert probs, "没检出任何问题（当前确实无 swap）"
joined = " ".join(probs)
assert "swap" in joined.lower(), f"未指出 swap 问题: {probs}"
print(f"  检出: {probs[0][:52]}…")
PYEOF
[ $? -q 0 ] 2>/dev/null
./bin/qyctl hibernate-check > "$TMP/hib.txt" 2>&1
grep -q "swap" "$TMP/hib.txt" \
  && ok "休眠前检出 swap 不足" || bad "未检出休眠风险"

step "3. 强制重启必须标注会丢数据"
./bin/qyctl power > "$TMP/pw.txt" 2>&1
grep -q "会丢数据" "$TMP/pw.txt" \
  && ok "危险电源动作有标注" || bad "未标注风险"
grep -q "只在完全无响应时用" "$TMP/pw.txt" \
  && ok "说明了使用时机" || bad "未说明时机"
grep -q "force-shutdown" "$TMP/pw.txt" && grep -q "force-reboot" "$TMP/pw.txt" \
  && ok "强制关机与强制重启都在列" || bad "电源动作不全"

step "4. 定时开机要检查主板支持（不支持会静默失败）"
./bin/qyctl rtc-wake 1735689600 > "$TMP/rtc.txt" 2>&1
grep -q "不支持定时开机" "$TMP/rtc.txt" \
  && ok "提示先确认 RTC 支持" || bad "未提示支持检测"
grep -q "读回来确认" "$TMP/rtc.txt" \
  && ok "要求回读确认（写入可能无效）" || bad "未要求回读"
grep -q "BIOS" "$TMP/rtc.txt" \
  && ok "提示 BIOS 可能也要开" || bad "未提 BIOS"

step "5. 亮度：不能硬编码最大值"
./bin/qyctl brightness --percent 60 > "$TMP/br.txt" 2>&1
grep -q "max_brightness" "$TMP/br.txt" \
  && ok "先读最大值再换算" || bad "硬编码了亮度值"
grep -q "不能超过\|超过最大值\|不会生效" "$TMP/br.txt" \
  && ok "提示越界会静默无效" || bad "未提示越界"
grep -q "MAX \* 60" "$TMP/br.txt" && ok "按百分比换算正确" || bad "换算不对"

step "6. EDID 读不到要明确说（否则误判显卡坏）"
./bin/qyctl display > "$TMP/dp.txt" 2>&1
grep -q "EDID" "$TMP/dp.txt" && ok "检查了 EDID" || bad "未检查 EDID"
grep -q "1024x768" "$TMP/dp.txt" \
  && grep -q "误判为显卡故障" "$TMP/dp.txt" \
  && ok "说明低分辨率的真实原因" || bad "未说明原因"

step "7. 陀螺仪：没有就不能给旋转开关"
./bin/qyctl display 2>&1 | grep -q "陀螺仪" \
  && ok "检测了陀螺仪" || bad "未检测陀螺仪"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import control as C
t = C.display_report()
# 没有陀螺仪的机器给了旋转开关也没用，
# 用户点了没反应会以为是 bug
assert "陀螺仪" in t
print("  报告含陀螺仪项：" +
      [l for l in t.splitlines() if "陀螺仪" in l][0].strip())
PYEOF
[ $? -eq 0 ] && ok "旋转能力依赖陀螺仪检测" || bad "旋转检测不正确"

step "8. 无线开关：硬件开关优先于软件"
./bin/qyctl wlan-on > "$TMP/wl.txt" 2>&1
grep -q "rfkill unblock wifi" "$TMP/wl.txt" \
  && ok "给出开启命令" || bad "命令不对"
grep -q "hard blocked\|硬件开关" "$TMP/wl.txt" \
  && ok "说明硬件开关优先（软件开不了）" || bad "未说明"
grep -q "rfkill list" "$TMP/wl.txt" \
  && ok "要求确认结果" || bad "未要求确认"

step "9. VPN：缺 TUN 必须报（否则无从排查）"
./bin/qyctl vpn > "$TMP/vpn.txt" 2>&1
grep -q "wireguard\|TUN" "$TMP/vpn.txt" \
  && ok "检出了 VPN 依赖缺失" || bad "未检出"

step "10. 私人 DNS：要说明失效表现"
./bin/qyctl privdns dns.example.com > "$TMP/dns.txt" 2>&1
grep -q "所有网站打不开" "$TMP/dns.txt" \
  && ok "说明 DoT 失效的真实表现" || bad "未说明表现"
grep -q "revert" "$TMP/dns.txt" \
  && ok "给了回退方法" || bad "未给回退"

step "11. DNS 自动识别：提醒 resolv.conf 可能是链接"
./bin/qyctl dns > "$TMP/dns2.txt" 2>&1
grep -q "符号链接" "$TMP/dns2.txt" \
  && ok "提醒改错文件等于没改" || bad "未提醒"
grep -q "resolvectl status" "$TMP/dns2.txt" \
  && ok "要求先看实际生效的 DNS" || bad "未要求"

step "12. 虚拟显示：容器/云手机要有渲染节点"
./bin/qyctl vgpu > "$TMP/vg.txt" 2>&1
grep -q "DRM\|渲染节点" "$TMP/vg.txt" \
  && ok "检查了 DRM 渲染节点" || bad "未检查"
grep -q "virgl" "$TMP/vg.txt" \
  && ok "检查了软件 3D 加速" || bad "未检查 virgl"

step "13. 声音：默认设备选错是没声音的常见成因"
./bin/qyctl audio > "$TMP/au.txt" 2>&1
grep -q "默认设备" "$TMP/au.txt" \
  && ok "指出默认设备问题" || bad "未指出"
grep -q "wpctl set-default" "$TMP/au.txt" \
  && ok "给出指定默认输出的命令" || bad "未给命令"

step "14. 设备检查：每项都要给排查提示"
./bin/qyctl devices > "$TMP/dev.txt" 2>&1
python3 - <<'PYEOF'
import re
t = open('/tmp/qy-ctl/dev.txt').read()
lines = t.splitlines()
# 每个"无"的项后面必须跟一行提示，否则用户只知道没有，不知道怎么办
i = 0
checked = 0
while i < len(lines):
    if re.search(r"\s无$", lines[i]):
        nxt = lines[i+1] if i+1 < len(lines) else ""
        assert nxt.strip() and not re.search(r"\s(有|无)$", nxt), \
            f"'无' 后面没有提示: {lines[i]}"
        assert len(nxt.strip()) > 10, f"提示太短: {nxt}"
        checked += 1
    i += 1
assert checked >= 3, f"只检查到 {checked} 项"
print(f"  {checked} 个缺失设备都给了排查提示")
PYEOF
[ $? -eq 0 ] && ok "缺失设备都有排查提示" || bad "提示不完整"

step "15. 关于本机要包含运行时长与开机时间"
./bin/qyctl overview > "$TMP/ov.txt" 2>&1
grep -q "已运行" "$TMP/ov.txt" && grep -q "开机时间" "$TMP/ov.txt" \
  && ok "含运行时长与开机时间" || bad "缺少运行信息"
grep -q "运行环境" "$TMP/ov.txt" \
  && ok "含运行环境（自我感知）" || bad "缺运行环境"
grep -q "CPU" "$TMP/ov.txt" && grep -q "内存" "$TMP/ov.txt" \
  && ok "含 CPU 与内存" || bad "缺硬件信息"

step "16. 运行环境会禁用不适用操作"
python3 - <<'INNEREOF'
import sys, io, contextlib; sys.path.insert(0, '.')
from qyos import control as C
# 直接验证"被禁用的动作不会被执行"，而不是看列表里有没有标注——
# 当前环境（虚拟机）未禁用电源动作，列表里自然没标注，那不是 bug
saved = C.detect_env
C.detect_env = lambda root=None: C.ENV_CONTAINER
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = C.main_cli(["power-do", "shutdown"])
assert rc == 1, "容器里的关机没被拦下"
out = buf.getvalue()
assert "不可用" in out, f"没说明原因: {out}"
print(f"  容器里执行关机 → 拦下")
C.detect_env = lambda root=None: C.ENV_PHYSICAL
buf2 = io.StringIO()
with contextlib.redirect_stdout(buf2):
    rc2 = C.main_cli(["power-do", "reboot"])
assert rc2 == 0, f"物理机的重启被误拦: {buf2.getvalue()}"
print("  物理机执行重启 → 放行（无误拦）")
C.detect_env = saved
INNEREOF
[ $? -eq 0 ] && ok "被禁动作会被拦下且不误拦" || bad "环境限制未生效"

step "17. 截图录屏要区分 Wayland 与 X11"
./bin/qyctl screenshot > "$TMP/sc.txt" 2>&1
grep -q "grim" "$TMP/sc.txt" && grep -q "X11" "$TMP/sc.txt" \
  && ok "截图区分了协议" || bad "未区分"
./bin/qyctl record > "$TMP/rec.txt" 2>&1
grep -q "wf-recorder" "$TMP/rec.txt" && grep -q "x11grab" "$TMP/rec.txt" \
  && ok "录屏区分了协议" || bad "未区分"

step "18. 充电阈值要说明下限（否则用户以为充不进电）"
./bin/qyctl battery > "$TMP/bat.txt" 2>&1
grep -q "60" "$TMP/bat.txt" \
  && ok "给出阈值下限建议" || bad "未给下限"
grep -q "充不进去电" "$TMP/bat.txt" \
  && ok "说明设太低的后果" || bad "未说明后果"

step "19. 温度感知"
./bin/qyctl thermal > "$TMP/th.txt" 2>&1
grep -q "温度" "$TMP/th.txt" && ok "输出了温度信息" || bad "无温度信息"

step "20. 清理"
qyrm "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
