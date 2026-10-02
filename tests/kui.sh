#!/usr/bin/env bash
# 内核模块 / 设备节点权限 / 输入设备与外设 专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-kui
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. 设备名 → 模块名 的翻译层必须存在"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import kmod as K
# 用户看到的是"我的 AX210 网卡"，内核里叫 iwlwifi。
# 没有这层映射用户根本不知道该加载什么
assert "iwlwifi" in K.modules_for("Intel Wi-Fi 6 AX210"), "AX210 没映射到 iwlwifi"
assert "iwlwifi" in K.modules_for("intel wireless 8265"), "8265 没映射"
assert "r8169" in K.modules_for("Realtek RTL8168"), "RTL8168 没映射"
assert "amdgpu" in K.modules_for("AMD Radeon RX 6700"), "AMD 显卡没映射"
assert "nvme" in K.modules_for("Samsung NVMe SSD"), "NVMe 没映射"
assert "uvcvideo" in K.modules_for("USB Camera"), "摄像头没映射"
print("  无线/有线/显卡/存储/摄像头 映射均正确")
# 反查：lsmod 里看到模块名要知道它管什么
assert "wi-fi" in K.module_desc("iwlwifi") or "wireless" in K.module_desc("iwlwifi")
print(f"  反查: iwlwifi → {K.module_desc('iwlwifi')}")
PYEOF
[ $? -eq 0 ] && ok "设备到模块的映射与反查正确" || bad "映射不正确"

step "2. 黑名单拼错必须报错（否则静默失效）"
./bin/qykmod blacklist iwlwif > "$TMP/bl.txt" 2>&1
grep -q "不存在" "$TMP/bl.txt" \
  && ok "拼错的模块名被拒绝" || bad "未拒绝拼错"
grep -q "黑名单不会生效" "$TMP/bl.txt" \
  && ok "说明了静默失效的后果" || bad "未说明后果"

step "3. 模块参数要落文件（命令行传参重启就没了）"
./bin/qykmod param iwlwifi power_save=false > "$TMP/pm.txt" 2>&1
grep -q "options iwlwifi power_save=false" "$TMP/pm.txt" \
  && ok "生成了正确格式" || bad "格式不对"
grep -q "modprobe.d" "$TMP/pm.txt" \
  && ok "提示写入持久化位置" || bad "未提示持久化"
grep -q "重启就没了" "$TMP/pm.txt" \
  && ok "说明了不做持久化的后果" || bad "未说明"

step "4. initramfs 缺模块会报'找不到根设备'，极易误判"
./bin/qykmod initramfs > "$TMP/ir.txt" 2>&1
grep -q "nvme\|ahci" "$TMP/ir.txt" && ok "存储控制器在列" || bad "缺失存储模块"
grep -q "找不到根设备" "$TMP/ir.txt" \
  && ok "说明了真实报错形态" || bad "未说明"
grep -q "误判" "$TMP/ir.txt" \
  && ok "点明会被误判为磁盘坏" || bad "未点明"

step "5. 设备节点必须归组，不能靠 chmod 777"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import udev as U
cls = {c.id: c for c in U.DEV_CLASSES}
# 不归组就只能 777，等于所有用户都能访问所有设备
assert cls["video"].group == "video", "摄像头组不对"
assert cls["audio"].group == "audio", "声音组不对"
assert cls["serial"].group == "dialout", "串口组不对"
assert cls["printer"].group == "lp", "打印机组不对"
assert cls["scanner"].group == "scanner", "扫描仪组不对"
assert cls["tpm"].group == "tss", "TPM 组不对"
print("  摄像头/声音/串口/打印/扫描/TPM 归属组均正确")
# 输入设备权限要紧：放宽可被键盘记录
assert cls["input"].mode == "0640", "输入设备权限过宽"
print(f"  输入设备 {cls['input'].mode}（放宽可被键盘记录）")
# 看门狗只给 root
assert cls["watchdog"].group == "root", "看门狗不该给普通组"
print("  看门狗仅 root（误触发会重启机器）")
PYEOF
[ $? -eq 0 ] && ok "设备归属组与权限位正确" || bad "权限配置不正确"

step "6. 权限过宽要警告（0666 = 所有人能读摄像头）"
./bin/qyudev usb 18d1 4ee7 --mode 0666 > "$TMP/wide.txt" 2>&1
grep -q "任何用户读写" "$TMP/wide.txt" \
  && ok "警告了 0666 的风险" || bad "未警告"
grep -q "摄像头" "$TMP/wide.txt" \
  && ok "给出具体后果" || bad "后果不具体"
./bin/qyudev usb 18d1 4ee7 --mode 0660 > "$TMP/ok.txt" 2>&1
grep -q "任何用户读写" "$TMP/ok.txt" \
  && bad "0660 被误报（误报比漏检更糟）" || ok "0660 不误报"

step "7. USB 规则按 VID/PID 匹配，不按 /dev 名"
./bin/qyudev usb 1a86 7523 --group dialout > "$TMP/usb.txt" 2>&1
grep -q "idVendor" "$TMP/usb.txt" && grep -q "idProduct" "$TMP/usb.txt" \
  && ok "按 VID/PID 匹配" || bad "未按 VID/PID"
grep -q "第二个同类设备" "$TMP/usb.txt" \
  && ok "说明了按 /dev 名会失效" || bad "未说明"
./bin/qyudev usb xyz 1234 > "$TMP/bad.txt" 2>&1
grep -q "4 位十六进制" "$TMP/bad.txt" \
  && ok "校验了 ID 格式" || bad "未校验格式"

step "8. ADB 没有 udev 规则会一直 unauthorized"
./bin/qyudev known adb > "$TMP/adb.txt" 2>&1
# 用子串而非整段匹配：整段里含 {} 时不同 grep 实现行为不一致，
# 会出现"功能正确却判失败"，最耗信任
grep -qF '=="18d1"' "$TMP/adb.txt" \
  && ok "生成了正确 VID" || bad "VID 不对"
grep -qF '=="4ee7"' "$TMP/adb.txt" \
  && ok "生成了正确 PID" || bad "PID 不对"
grep -q "uaccess" "$TMP/adb.txt" \
  && ok "加了 uaccess 标签" || bad "缺 uaccess"
grep -q "unauthorized" "$TMP/adb.txt" \
  && ok "说明了症状（一直 unauthorized）" || bad "未说明症状"

step "9. 规则改了必须重载，否则以为写了没用"
./bin/qyudev reload > "$TMP/rl.txt" 2>&1
grep -q "udevadm control --reload" "$TMP/rl.txt" \
  && ok "给出重载命令" || bad "未给命令"
grep -q "不生效" "$TMP/rl.txt" \
  && ok "说明不重载就不生效" || bad "未说明"

step "10. 缺组会导致规则写了但没用"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import udev as U
# GROUP= 引用了不存在的组，规则静默失效
probs = U.group_check(__import__('pathlib').Path('/'))
for p in probs:
    assert "groupadd" in p, f"没给出创建命令: {p}"
    assert "不会生效" in p, f"没说明后果: {p}"
print(f"  检出 {len(probs)} 个缺失组，都给了创建命令与后果说明")
if probs:
    print(f"  例: {probs[0][:56]}…")
PYEOF
[ $? -eq 0 ] && ok "缺失组有检出与修复指引" || bad "缺组未正确提示"

step "11. 触摸板走 PS/2 就是降级（最常见的'不好用'）"
cat > "$TMP/inp.txt" <<'EOF'
I: Bus=0019 Vendor=0000 Product=0000 Version=0000
N: Name="SynPS/2 Synaptics TouchPad"
P: Phys=isa0060/serio1/input0
H: Handlers=mouse0 event7
EOF
./bin/qyio touchpad --devices-file "$TMP/inp.txt" > "$TMP/tp.txt" 2>&1
grep -q "降级" "$TMP/tp.txt" \
  && ok "识别出走的是 PS/2" || bad "未识别降级"
grep -q "多指手势" "$TMP/tp.txt" \
  && ok "说明了缺失的能力" || bad "未说明"

step "12. I2C 触摸板正常时不该被误报降级"
cat > "$TMP/inp2.txt" <<'EOF'
N: Name="ELAN Touchpad"
P: Phys=i2c-ELAN0001:00
H: Handlers=mouse1 event8
EOF
./bin/qyio touchpad --devices-file "$TMP/inp2.txt" > "$TMP/tp2.txt" 2>&1
grep -q "完整" "$TMP/tp2.txt" \
  && ok "I2C 触摸板判为完整" || bad "被误判为降级"
grep -q "降级" "$TMP/tp2.txt" \
  && bad "误报降级（误报比漏检更糟）" || ok "无误报"

step "13. 数位板没压感：笔能用但压力恒定"
./bin/qyio tablet --brand wacom > "$TMP/tb.txt" 2>&1
grep -q "压力恒定" "$TMP/tb.txt" \
  && ok "说明了真实表现" || bad "未说明"
grep -q "不会有任何报错" "$TMP/tb.txt" \
  && ok "点明无报错（最难排查）" || bad "未点明"
./bin/qyio tablet 2>&1 | grep -q "已收录" \
  && ok "未匹配时列出全部品牌" || bad "未列出"

step "14. 打印机驱动没配对会导致任务卡住"
./bin/qyio printer myprn ipp://192.168.1.9 > "$TMP/pr.txt" 2>&1
grep -q "没有指定驱动" "$TMP/pr.txt" \
  && ok "警告缺驱动" || bad "未警告"
grep -q "输出乱码\|卡住" "$TMP/pr.txt" \
  && ok "说明了后果" || bad "未说明后果"

step "15. 外接显示器不亮的排查顺序"
./bin/qyio screen-hint > "$TMP/sc.txt" 2>&1
grep -q "disconnected" "$TMP/sc.txt" \
  && ok "区分了未连接与已连接不亮" || bad "未区分"
grep -q "1024x768" "$TMP/sc.txt" \
  && ok "指出低分辨率是 EDID 问题" || bad "未指出"
./bin/qyio screen --layout extend > "$TMP/ex.txt" 2>&1
grep -q "right-of\|--right" "$TMP/ex.txt" \
  && ok "生成了扩展布局命令" || bad "布局命令不对"

step "16. RAID 降级必须告警（再坏一块就丢数据）"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import io as I
import io as _io
# 造一份降级的 mdstat
degraded = """Personalities : [raid1]
md0 : active raid1 sdb1[1]
      488386496 blocks super 1.2 [2/1] [_U]
"""
orig = __import__('pathlib').Path.read_text
def fake(self, *a, **k):
    if str(self).endswith("mdstat"):
        return degraded
    return orig(self, *a, **k)
__import__('pathlib').Path.read_text = fake
probs = I.raid_check()
__import__('pathlib').Path.read_text = orig
found = [p for p in probs if "降级" in p or "缺失" in p]
assert found, f"没检出降级: {probs}"
print(f"  检出: {found[0][:52]}…")
assert any("丢数据" in p for p in probs), "没说明紧急性"
print("  并说明了'再坏一块就丢数据'的紧急性")
PYEOF
[ $? -eq 0 ] && ok "RAID 降级被检出并说明紧急性" || bad "RAID 检查不正确"

step "17. TPM 缺失要说明后果"
./bin/qyio tpm > "$TMP/tpm.txt" 2>&1
grep -q "tpm_tis\|没有" "$TMP/tpm.txt" \
  && ok "检查了 TPM 设备" || bad "未检查"
grep -q "暴力破解" "$TMP/tpm.txt" \
  && ok "说明了无 TPM 的后果" || bad "未说明后果"

step "18. SD 读卡器读不出不报错"
./bin/qyio storage > "$TMP/sd.txt" 2>&1
grep -q "SD" "$TMP/sd.txt" \
  && ok "检查了 SD 读卡器控制器" || bad "未检查"
grep -q "不会有任何反应\|不会报错" "$TMP/sd.txt" \
  && ok "点明静默失败" || bad "未点明"

step "19. 卸载提醒（不卸载直接拔会损坏数据）"
./bin/qyio mount /dev/sdb1 > "$TMP/um.txt" 2>&1
grep -q "unmount" "$TMP/um.txt" \
  && ok "给了卸载命令" || bad "未给"
grep -q "损坏数据" "$TMP/um.txt" \
  && ok "说明了直接拔的后果" || bad "未说明"

step "20. 手柄蓝牙配对成功但没反应 = 模块没加载"
./bin/qyio gamepad > "$TMP/gp.txt" 2>&1
grep -q "xpad" "$TMP/gp.txt" && grep -q "hid_sony" "$TMP/gp.txt" \
  && ok "列出了各品牌驱动" || bad "驱动不全"
grep -q "不是配对问题" "$TMP/gp.txt" \
  && ok "点明不是配对问题（避免排查跑偏）" || bad "未点明"

step "21. 清理"
qyrm "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
