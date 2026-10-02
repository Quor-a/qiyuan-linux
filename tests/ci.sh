#!/usr/bin/env bash
# 持续集成与可复现构建专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
# 临时目录放 /tmp：工作区文件系统（virtiofs）上 cp -r 整个项目
# 会失败或极慢，副本建不起来，后续破坏实验就全部误报
TMP=/tmp/qy-ci
for _ in 1 2 3; do rm -rf "$TMP" 2>/dev/null; [ -e "$TMP" ] || break; sleep 1; done
mkdir -p "$TMP"

# rm -rf 在这套文件系统上可能报 Directory not empty，要重试。
# 不重试的话构建目录清不干净，下一轮会用到上轮的产物，
# 于是"两次构建是否相同"这个测试根本测的是缓存而不是可复现性。
qyrm(){
  for _ in 1 2 3 4 5; do
    rm -rf "$@" 2>/dev/null
    gone=1
    for t in "$@"; do [ -e "$t" ] && gone=0; done
    [ "$gone" -eq 1 ] && return 0
    sleep 1
  done
  return 1
}

step "1. 可复现 tar：条目排序 + 时间戳钳制 + 属主归一"
python3 - <<'PYEOF'
import sys, os, shutil; sys.path.insert(0, '.')
from qyos import repro as RP, util
from pathlib import Path
d = Path('/tmp/qy-rp-src'); shutil.rmtree(d, ignore_errors=True)
(d/'usr'/'bin').mkdir(parents=True)
(d/'usr'/'bin'/'a').write_text('hello')
(d/'usr'/'bin'/'b').write_text('world'*100)
os.utime(d/'usr'/'bin'/'a', (1000000, 1000000))
os.utime(d/'usr'/'bin'/'b', (2000000, 2000000))

util.make_tar(d, Path('/tmp/qy-old.tar.gz'), 'gz')
RP.make_repro_tar(d, Path('/tmp/qy-new.tar.gz'), 'gz', epoch=1000)
old = Path('/tmp/qy-old.tar.gz').read_bytes()
new = Path('/tmp/qy-new.tar.gz').read_bytes()
# 旧实现 gzip 头带当前时间
assert int.from_bytes(old[4:8], 'little') != 0, "旧实现应该有时间戳"
assert int.from_bytes(new[4:8], 'little') == 0, "可复现实现必须固定为 0"
print(f"  旧 gzip 头 mtime={int.from_bytes(old[4:8],'little')}，新=0")
# 连打两次必须字节相同
RP.make_repro_tar(d, Path('/tmp/qy-new2.tar.gz'), 'gz', epoch=1000)
same, pos, why = RP.compare_bytes(new, Path('/tmp/qy-new2.tar.gz').read_bytes())
assert same, f"两次不同: {why}"
print("  连打两次逐字节相同")
PYEOF
[ $? -eq 0 ] && ok "可复现 tar 三次验证均正确" || bad "可复现 tar 不正确"

step "2. gzip 头时间戳检查"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import repro as RP
from pathlib import Path
# 带时间戳的必须被检出
assert RP.check_gzip_header(Path('/tmp/qy-old.tar.gz')), "未检出 gzip 时间戳"
print("  旧实现 → 检出")
assert not RP.check_gzip_header(Path('/tmp/qy-new.tar.gz')), "可复现的被误报"
print("  可复现 → 无误报")
PYEOF
[ $? -eq 0 ] && ok "gzip 时间戳检出且不误报" || bad "gzip 检查不正确"

step "3. 未设 SOURCE_DATE_EPOCH 时两次构建确实不同"
qyrm var/work var/pkgs
env -u SOURCE_DATE_EPOCH ./bin/qybuild libqydemo qydemo --force >/dev/null 2>&1
A=$(sha256sum var/pkgs/qydemo-0.1.0-1.x86_64.qyp 2>/dev/null | awk '{print $1}')
qyrm var/work
env -u SOURCE_DATE_EPOCH ./bin/qybuild libqydemo qydemo --force >/dev/null 2>&1
B=$(sha256sum var/pkgs/qydemo-0.1.0-1.x86_64.qyp 2>/dev/null | awk '{print $1}')
# 两次都必须真产出包，否则"不同"可能只是两次都没产物
[ -n "$A" ] && [ -n "$B" ] && ok "两次都成功产出包" || bad "构建没产出包"
[ "$A" != "$B" ] && ok "未设 epoch 时两次不同（说明检查有意义）" \
  || bad "未设 epoch 竟然相同，检查无从谈起"

step "4. 设了 SOURCE_DATE_EPOCH 后两次构建逐字节相同"
qyrm var/work var/pkgs
SOURCE_DATE_EPOCH=1700000000 ./bin/qybuild libqydemo qydemo --force >/dev/null 2>&1
A=$(sha256sum var/pkgs/qydemo-0.1.0-1.x86_64.qyp 2>/dev/null | awk '{print $1}')
qyrm var/work
SOURCE_DATE_EPOCH=1700000000 ./bin/qybuild libqydemo qydemo --force >/dev/null 2>&1
B=$(sha256sum var/pkgs/qydemo-0.1.0-1.x86_64.qyp 2>/dev/null | awk '{print $1}')
# 沙盒文件系统偶发 rm 不干净导致第二次构建没产出。
# 重试一次——这是环境问题不是代码问题，不重试的话测试会随机变红，
# 而随机变红的测试等于没有测试
if [ -z "$B" ]; then
  qyrm var/work var/pkgs
  SOURCE_DATE_EPOCH=1700000000 ./bin/qybuild libqydemo qydemo --force >/dev/null 2>&1
  B=$(sha256sum var/pkgs/qydemo-0.1.0-1.x86_64.qyp 2>/dev/null | awk '{print $1}')
fi
[ -n "$A" ] && [ -n "$B" ] && ok "两次都成功产出包" || bad "构建没产出包"
echo "  A=${A:0:16}…"
echo "  B=${B:0:16}…"
[ "$A" = "$B" ] && ok "两次构建逐字节相同" || bad "可复现构建失败"

step "5. 可复现检查：可复现的包零问题"
SOURCE_DATE_EPOCH=1700000000 ./bin/qybuild qydemo libqydemo --force \
  --sign var/repo/keys/qiyuan >/dev/null 2>&1
./bin/qyrepro check var/pkgs/qydemo-0.1.0-1.x86_64.qyp > "$TMP/chk.txt" 2>&1
grep -q "通过" "$TMP/chk.txt" && ok "可复现包检查通过（无误报）" \
  || { bad "可复现包被误报"; cat "$TMP/chk.txt"; }

step "6. 可复现检查：非可复现的包要被检出"
qyrm var/work
env -u SOURCE_DATE_EPOCH ./bin/qybuild qydemo --force >/dev/null 2>&1
./bin/qyrepro check var/pkgs/qydemo-0.1.0-1.x86_64.qyp > "$TMP/chk2.txt" 2>&1
grep -q "时间戳" "$TMP/chk2.txt" && ok "检出时间戳问题" || bad "未检出时间戳"
grep -q "属主" "$TMP/chk2.txt" && ok "检出属主未归一" || bad "未检出属主"
grep -q "SOURCE_DATE_EPOCH" "$TMP/chk2.txt" \
  && ok "给出了怎么修" || bad "未说明修法"

step "7. epoch 来源"
./bin/qyrepro epoch > "$TMP/ep.txt" 2>&1
grep -qE "SOURCE_DATE_EPOCH|git|未设定" "$TMP/ep.txt" \
  && ok "能说明时间戳来源" || bad "epoch 输出不明"
SOURCE_DATE_EPOCH=1234567890 ./bin/qyrepro epoch | grep -q "1234567890" \
  && ok "优先使用环境变量" || bad "环境变量未生效"

step "8. CI：变更影响分析"
./bin/qyci plan --changed zlib > "$TMP/p1.txt" 2>&1
grep -q "需要重编" "$TMP/p1.txt" && ok "算出重编闭包" || bad "无重编计划"
python3 - <<'PYEOF'
import re, os, pathlib
t = pathlib.Path(os.environ["TMP"] + "/p1.txt").read_text()
n = int(re.search(r"需要重编 (\d+) 个包", t).group(1))
assert n > 10, f"改 zlib 影响面不该这么小: {n}"
print(f"  改 zlib → 重编 {n} 个包")
PYEOF
[ $? -eq 0 ] && ok "影响面规模合理" || bad "影响面异常"
./bin/qyci plan --changed ncurses > "$TMP/p2.txt" 2>&1
grep -q "python" "$TMP/p2.txt" && grep -q "bash" "$TMP/p2.txt" \
  && ok "改 ncurses 牵出 bash 与 python" || bad "闭包内容不对"
grep -q "第0层" "$TMP/p2.txt" && grep -q "第1层" "$TMP/p2.txt" \
  && ok "分了并行层" || bad "未分层"

step "9. CI 能从 git 检出真实改动"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import ci
from pathlib import Path
files = ci.git_changed_files(Path('.'))
assert files, "git 没检出改动文件（本仓库应当有未提交或最近的改动）"
print(f"  git 改动 {len(files)} 个文件，例如 {files[0]}")
mapped = ci.detect_changed(Path('.'))
print(f"  映射到包: {mapped[:5]}")
PYEOF
[ $? -eq 0 ] && ok "git 变更检测可用" || bad "git 变更检测失败"

step "10. 发布门禁：干净状态全部通过"
# 前面几步刻意构建过未签名的包，这里必须彻底清干净再重编。
# 只清 var/work 的话，--force 之外的跳过逻辑可能沿用旧的未签名产物，
# 于是"干净状态"根本不干净，门禁报的是上一步的残留而不是真实状态。
qyrm var/pkgs var/work
# 只编演示包：门禁针对"发布集"（仓库里实际有的包），
# 编全部 177 个配方会让这一步跑几分钟，而门禁结论完全一样
./bin/qybuild filesystem qyinit libqydemo qydemo \
  --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
./bin/qyci gates > "$TMP/g.txt" 2>&1
for g in "锁定 sha256" "包已签名" "索引与签名匹配" "加固项" "构建机路径" "版本未回退"; do
  grep -q "\[通过\].*$g" "$TMP/g.txt" \
    && ok "门禁通过：$g" || { bad "门禁未通过：$g"; grep "$g" "$TMP/g.txt"; }
done
grep -q "另有.*个配方尚未就绪" "$TMP/g.txt" \
  && ok "未就绪的配方单独提醒（不阻塞发布）" || bad "未提示未就绪配方"

step "11. 门禁真能拦截（在副本上做破坏实验）"
# 所有破坏操作都在副本里做，且用绝对路径执行——
# 用 cd 的话一旦某步失败，后续命令会落回主工作区把主仓库改坏
REPO="$TMP/repo"
qyrm "$REPO"; mkdir -p "$REPO"
cp -r bin qyos recipes var tests "$REPO"/ 2>/dev/null

python3 -c "
import json, pathlib
p = pathlib.Path('$REPO/var/repo/x86_64/index.json')
d = json.loads(p.read_text())
n = 0
for e in d['packages']:
    if e['name'] == 'qydemo':
        e['sha256'] = '0'*64; n += 1
p.write_text(json.dumps(d))
assert n, '索引里没有 qydemo，无法做篡改实验'
print('  已篡改 qydemo 的哈希')
"
(cd "$REPO" && ./bin/qyci gates --only index) > "$TMP/bad1.txt" 2>&1
grep -q "拦截" "$TMP/bad1.txt" && grep -q "哈希与实际文件不符" "$TMP/bad1.txt" \
  && ok "篡改索引哈希 → 拦截" || { bad "篡改索引未被拦截"; cat "$TMP/bad1.txt"; }

rm -f "$REPO/var/repo/x86_64/index.json.sig"
(cd "$REPO" && ./bin/qyci gates --only index) > "$TMP/bad2.txt" 2>&1
grep -q "索引没有签名文件" "$TMP/bad2.txt" \
  && ok "删掉索引签名 → 拦截" || bad "缺索引签名未被拦截"

qyrm "$REPO/var/repo/x86_64" "$REPO/var/pkgs" "$REPO/var/work"
(cd "$REPO" && ./bin/qybuild libqydemo qydemo --force && ./bin/qyrepo sync) \
  >/dev/null 2>&1
(cd "$REPO" && ./bin/qyci gates --only signed) > "$TMP/bad3.txt" 2>&1
grep -q "包未签名" "$TMP/bad3.txt" \
  && ok "未签名的包 → 拦截" || { bad "未签名未被拦截"; cat "$TMP/bad3.txt"; }

step "12. 门禁失败要说清怎么修"
grep -q "修：" "$TMP/bad1.txt" && grep -q "修：" "$TMP/bad3.txt" \
  && ok "每条失败都给了修复方法" || bad "失败信息没有修法"
grep -q "为什么重要" "$TMP/bad1.txt" \
  && ok "说明了这项为什么重要" || bad "未说明重要性"

step "13. 门禁自身出错不能静默通过"
python3 -c "
import pathlib
p = pathlib.Path('$REPO/var/repo/x86_64/broken.qyp')
p.write_bytes(b'not a package' * 10)
"
(cd "$REPO" && ./bin/qyci gates --only signed) > "$TMP/bad4.txt" 2>&1
grep -q "无法读取" "$TMP/bad4.txt" \
  && ok "损坏的包被检出而非跳过" || bad "损坏包被静默忽略"

step "14. 清理与主仓库自检"
qyrm "$TMP"
ok "测试产物已清理"
mkdir -p "$TMP"
./bin/qyci gates > "$TMP/self.txt" 2>&1
grep -q "全部通过" "$TMP/self.txt" \
  && ok "主仓库未被破坏实验污染" || { bad "主仓库被污染"; head -6 "$TMP/self.txt"; }

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
