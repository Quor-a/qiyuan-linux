#!/usr/bin/env bash
# 权限框架 / 媒体与个人数据 / 通知与窗口 / 回收站与剪贴板 专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-pmn
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. 硬件在但没框架：必须分开报硬件层与框架层"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import perms as P
r = P.capability_readiness()
# 只报"可用/不可用"会把两类问题混为一谈：
# 用户照着提示装了固件发现还是不行
for cid, info in r.items():
    assert "hardware" in info and "framework" in info, f"{cid} 没分层"
print(f"  共 {len(r)} 项能力，全部区分硬件层与框架层")
# 相机要有框架包声明
c = P.CAP_BY_ID["camera"]
assert c.framework_pkg, "相机没声明框架包"
assert c.device_hint, "相机没声明设备节点"
print(f"  相机: 设备 {c.device_hint} / 框架 {c.framework_pkg}")
PYEOF
[ $? -eq 0 ] && ok "就绪度分硬件层与框架层" || bad "未分层"

step "2. 敏感能力默认不放行"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import perms as P
# 默认放行的权限等于没有权限
assert P.DEFAULT_POLICY["critical"] == "deny", "极高敏感度默认不是拒绝"
assert P.DEFAULT_POLICY["high"] == "ask", "高敏感度默认不是询问"
print(f"  极高→{P.DEFAULT_POLICY['critical']}  "
      f"高→{P.DEFAULT_POLICY['high']}  "
      f"中→{P.DEFAULT_POLICY['medium']}")
# 短信（critical）默认就该被拒
st = P.get_state(P.Path('/tmp/qy-pmn'), "any", "sms")
assert st == "deny", f"sms 默认 {st}"
print("  短信（极高敏感度）默认拒绝")
PYEOF
[ $? -eq 0 ] && ok "敏感能力默认拒绝或询问" || bad "默认策略过松"

step "3. 仅前台允许：后台偷偷定位的正解"
qyrm "$TMP/p"; mkdir -p "$TMP/p"
./bin/qyperms --root "$TMP/p" grant nav location allow-foreground >/dev/null 2>&1
./bin/qyperms --root "$TMP/p" check nav location >/dev/null 2>&1 \
  && ok "前台时允许" || bad "前台被误拒"
./bin/qyperms --root "$TMP/p" check nav location --background \
  > "$TMP/bg.txt" 2>&1
grep -q "仅在处于前台时" "$TMP/bg.txt" \
  && ok "后台时拒绝并说明理由" || bad "后台未拒绝"
grep -q "改为「允许」" "$TMP/bg.txt" \
  && ok "告诉用户怎么放开" || bad "未给放开方式"

step "4. 危险能力组合必须被点出来"
qyrm "$TMP/p2"; mkdir -p "$TMP/p2"
./bin/qyperms --root "$TMP/p2" grant spy monitor allow >/dev/null 2>&1
./bin/qyperms --root "$TMP/p2" grant spy background allow \
  > "$TMP/cb.txt" 2>&1
grep -q "键盘记录器" "$TMP/cb.txt" \
  && ok "截屏+后台 被识别为危险组合" || bad "未识别"
qyrm "$TMP/p3"; mkdir -p "$TMP/p3"
./bin/qyperms --root "$TMP/p3" grant ph overlay allow >/dev/null 2>&1
./bin/qyperms --root "$TMP/p3" grant ph background allow \
  > "$TMP/cb2.txt" 2>&1
grep -q "钓鱼" "$TMP/cb2.txt" \
  && ok "悬浮窗+后台 被识别" || bad "未识别"

step "5. 被拒绝时要给出可操作的提示"
./bin/qyperms --root "$TMP/p2" check spy sms > "$TMP/dn.txt" 2>&1
grep -q "qyperms grant" "$TMP/dn.txt" \
  && ok "给出了开启命令" || bad "未给命令"
grep -q "框架支持包" "$TMP/dn.txt" \
  && ok "提示检查框架支持包" || bad "未提示框架"

step "6. 撤销授权：卸载时不留后门"
qyrm "$TMP/p4"; mkdir -p "$TMP/p4"
./bin/qyperms --root "$TMP/p4" grant app1 camera allow >/dev/null 2>&1
./bin/qyperms --root "$TMP/p4" grant app1 microphone allow >/dev/null 2>&1
n=$(./bin/qyperms --root "$TMP/p4" revoke app1 2>&1 | grep -oE "[0-9]+ 项")
echo "$n" | grep -q "^2 项" \
  && ok "撤销了全部 2 项授权" || bad "撤销数量不对"
[ "$(./bin/qyperms --root "$TMP/p4" list --package app1 | wc -l)" -le 1 ] \
  && ok "记录已清空（不给不存在的包留后门）" || bad "仍有残留"

step "7. 相机独占：同时开两个会互相抢"
qyrm "$TMP/m"; mkdir -p "$TMP/m"
./bin/qymedia --root "$TMP/m" request /dev/video0 cam1 >/dev/null 2>&1
./bin/qymedia --root "$TMP/m" request /dev/video0 cam2 \
  > "$TMP/occ.txt" 2>&1
grep -q "正被 cam1 占用" "$TMP/occ.txt" \
  && ok "第二个申请被拒绝" || bad "未独占"
grep -q "黑屏" "$TMP/occ.txt" \
  && ok "说明了后果（黑屏且不报错）" || bad "未说明后果"
./bin/qymedia --root "$TMP/m" release /dev/video0 cam1 >/dev/null 2>&1
./bin/qymedia --root "$TMP/m" request /dev/video0 cam2 >/dev/null 2>&1 \
  && ok "释放后能拿到" || bad "释放后仍拿不到"

step "8. 应用声明：后台用却没声明用 = 自相矛盾"
qyrm "$TMP/m2"; mkdir -p "$TMP/m2"
./bin/qymedia --root "$TMP/m2" declare app --uses camera \
  --background microphone > "$TMP/dc.txt" 2>&1
grep -q "自相矛盾" "$TMP/dc.txt" \
  && ok "检出矛盾声明" || bad "未检出"
./bin/qymedia --root "$TMP/m2" declare app2 --uses microphone \
  --background microphone > "$TMP/dc2.txt" 2>&1
grep -q "后台使用" "$TMP/dc2.txt" \
  && ok "后台用敏感能力会提醒" || bad "未提醒"

step "9. 全屏通知只能给紧急的"
./bin/qynotify fullscreen normal > "$TMP/fs.txt" 2>&1
grep -q "不能用全屏" "$TMP/fs.txt" \
  && ok "普通通知不能用全屏" || bad "未限制"
grep -q "劫持屏幕" "$TMP/fs.txt" \
  && ok "说明了理由" || bad "未说明理由"
./bin/qynotify fullscreen critical >/dev/null 2>&1 \
  && ok "紧急通知允许全屏" || bad "紧急被误拒"

step "10. 免打扰要有例外（否则紧急联系人打不进来）"
./bin/qynotify dnd --on > "$TMP/dnd.txt" 2>&1
grep -q "没有设置例外联系人" "$TMP/dnd.txt" \
  && ok "提醒未设例外联系人" || bad "未提醒"
./bin/qynotify dnd --on --contacts mom dad 2>&1 \
  | grep -q "例外联系人: mom、dad" \
  && ok "能设例外联系人" || bad "不能设"

step "11. 画中画要限制类别"
./bin/qynotify pip game > "$TMP/pip.txt" 2>&1
grep -q "不能使用画中画" "$TMP/pip.txt" \
  && ok "非视频类被拒" || bad "未限制"
./bin/qynotify pip video >/dev/null 2>&1 \
  && ok "视频类允许" || bad "视频被误拒"

step "12. 悬浮窗有尺寸下限"
./bin/qynotify floating 30 > "$TMP/fl.txt" 2>&1
grep -q "小于下限" "$TMP/fl.txt" \
  && ok "过小悬浮窗被拒" || bad "未限制"
./bin/qynotify floating 200 >/dev/null 2>&1 \
  && ok "正常尺寸允许" || bad "被误拒"

step "13. 热更新必须签名且经审计"
./bin/qynotify hot-update > "$TMP/hu.txt" 2>&1
grep -q "未签名" "$TMP/hu.txt" && ok "未签名被拒" || bad "未校验签名"
# 注意：脚本开了 pipefail，而被拒的命令本身返回 1，
# 直接 `cmd | grep -q` 会因为 pipefail 判成失败。先落文件再 grep
./bin/qynotify hot-update --signed > "$TMP/hu2.txt" 2>&1
grep -q "未经发行版审计" "$TMP/hu2.txt" \
  && ok "未审计被拒（无法复现现场）" || bad "未校验审计"
./bin/qynotify hot-update --signed --audited >/dev/null 2>&1 \
  && ok "签名且审计通过" || bad "被误拒"

step "14. 通知分组：一个应用刷屏不能挤掉别人"
./bin/qynotify group 50 > "$TMP/gr.txt" 2>&1
grep -q "折叠为 1 条" "$TMP/gr.txt" \
  && ok "50 条折叠成 1 条" || bad "未折叠"
grep -q "等 50 条" "$TMP/gr.txt" && ok "显示总条数" || bad "未显示总数"

step "15. 息屏显示内容受限（防止烧屏）"
./bin/qynotify aod > "$TMP/aod.txt" 2>&1
grep -q "偏移" "$TMP/aod.txt" \
  && grep -q "烧屏" "$TMP/aod.txt" \
  && ok "说明了偏移与烧屏的关系" || bad "未说明"

step "16. 回收站：删除要能后悔"
qyrm "$TMP/t"; mkdir -p "$TMP/t/home"
echo "important" > "$TMP/t/home/doc.txt"
./bin/qyfiles --root "$TMP/t" trash "$TMP/t/home/doc.txt" >/dev/null 2>&1
[ ! -e "$TMP/t/home/doc.txt" ] && ok "文件已移出原位置" || bad "未移出"
./bin/qyfiles --root "$TMP/t" trash-list 2>&1 | grep -q "doc.txt" \
  && ok "回收站记录了原路径" || bad "未记原路径"
NAME=$(python3 -c "
import json;print(json.load(open('$TMP/t/var/lib/qytrash/index.json'))['items'][0]['name'])")
./bin/qyfiles --root "$TMP/t" restore "$NAME" >/dev/null 2>&1
[ -f "$TMP/t/home/doc.txt" ] \
  && ok "还原回到原位置" || bad "还原失败"

step "17. 还原时目标被占用不能覆盖"
qyrm "$TMP/t2"; mkdir -p "$TMP/t2/home"
echo "old" > "$TMP/t2/home/doc.txt"
./bin/qyfiles --root "$TMP/t2" trash "$TMP/t2/home/doc.txt" >/dev/null 2>&1
echo "new file" > "$TMP/t2/home/doc.txt"     # 用户后来新建了同名文件
NAME=$(python3 -c "
import json;print(json.load(open('$TMP/t2/var/lib/qytrash/index.json'))['items'][0]['name'])")
./bin/qyfiles --root "$TMP/t2" restore "$NAME" > "$TMP/rs.txt" 2>&1
grep -q "已被占用" "$TMP/rs.txt" \
  && ok "拒绝覆盖（那可能是用户后来的新文件）" || bad "会覆盖"
grep -q "new file" "$TMP/t2/home/doc.txt" \
  && ok "新文件未被破坏" || bad "新文件被覆盖（严重）"

step "18. 分享不能直接给原路径"
mkdir -p "$TMP/sh"; echo x > "$TMP/sh/f.txt"
./bin/qyfiles --root "$TMP/sh" share "$TMP/sh/f.txt" --to app \
  > "$TMP/shr.txt" 2>&1
grep -q "暴露" "$TMP/shr.txt" \
  && ok "说明了直接给路径的风险" || bad "未说明"
grep -q "副本" "$TMP/shr.txt" && ok "走副本分享" || bad "未走副本"

step "19. 导入压缩包要先解压"
python3 -c "
import zipfile
with zipfile.ZipFile('$TMP/sh/a.zip','w') as z: z.writestr('x.txt','x')"
mkdir -p "$TMP/sh/dest"
./bin/qyfiles --root "$TMP/sh" import-check "$TMP/sh/a.zip" "$TMP/sh/dest" \
  > "$TMP/imp.txt" 2>&1
grep -q "压缩包" "$TMP/imp.txt" \
  && ok "提示先解压" || bad "未提示"
grep -q "qyfiles extract" "$TMP/imp.txt" \
  && ok "给出解压命令" || bad "未给命令"

step "20. 快捷键冲突必须能查出来"
./bin/qyfiles shortcuts --app-keys "mycopy=Ctrl+C" 2>&1 \
  | grep -q "同时占用" \
  && ok "检出冲突" || bad "未检出"
./bin/qyfiles shortcuts --app-keys "mine=Ctrl+K" 2>&1 \
  | grep -q "冲突" \
  && bad "无冲突却报冲突（误报）" || ok "无冲突不误报"

step "21. 复制要保留时间戳"
./bin/qyfiles copy /tmp/a /tmp/b > "$TMP/cp.txt" 2>&1
grep -q "\-p\|\-a" "$TMP/cp.txt" \
  && ok "用了保留时间戳的参数" || bad "未保留时间戳"

step "22. 清理"
qyrm "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
