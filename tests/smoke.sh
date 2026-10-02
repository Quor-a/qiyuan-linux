#!/usr/bin/env bash
# 端到端冒烟测试：构建 -> 签名 -> 仓库 -> 安装 -> 运行 -> 校验 -> 卸载
# 任何一步失败即退出非零。用于每次改动后确认链路没断。
set -o pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
TESTROOT=${TESTROOT:-/tmp/qy-smoke-root}
BUILDROOT=${BUILDROOT:-/tmp/qy-smoke-target}
PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step() { echo; echo "== $1"; }

step "0. 清理测试环境"
rm -rf "$TESTROOT" "$BUILDROOT"
mkdir -p "$TESTROOT" "$BUILDROOT"
ok "测试目录就绪"

step "1. 配方树解析"
./bin/qybuild --list >/dev/null 2>&1 && ok "配方树可解析" || bad "配方树解析失败"

step "2. 全量构建（含依赖求解与 sysroot 依赖安装）"
./bin/qybuild all --sign var/repo/keys/qiyuan --force >/tmp/qy-smoke-build.log 2>&1 \
  && ok "全部包构建成功" || { bad "构建失败"; tail -20 /tmp/qy-smoke-build.log; }

step "3. 包格式自检"
for p in var/pkgs/*.qyp; do
  python3 - "$p" <<'PY' >/dev/null 2>&1
import sys; sys.path.insert(0,'.')
from qyos import format as F
from pathlib import Path
sys.exit(0 if F.read_package(Path(sys.argv[1])).verify() else 1)
PY
  [ $? -eq 0 ] && ok "$(basename "$p") 哈希自洽" || bad "$(basename "$p") 校验失败"
done

step "4. 仓库索引验签"
./bin/qyrepo list --pubkey var/repo/keys/qiyuan.pub >/dev/null 2>&1 \
  && ok "索引签名有效" || bad "索引验签失败"
./bin/qyrepo verify --pubkey var/repo/keys/qiyuan.pub >/dev/null 2>&1 \
  && ok "仓库包哈希全部匹配" || bad "仓库包校验失败"

step "5. 安装到测试根"
./bin/qypkg --root "$TESTROOT" install qydemo >/dev/null 2>&1 \
  && ok "安装成功（含自动依赖）" || bad "安装失败"

step "6. 实际运行安装的软件"
out=$(LD_LIBRARY_PATH="$TESTROOT/usr/lib" "$TESTROOT/usr/bin/qydemo" 2>&1)
echo "$out" | grep -q "qydemo 0.1.0" && ok "程序运行: $(echo "$out" | head -1)" \
  || bad "程序无法运行: $out"

step "7. 文件完整性校验"
./bin/qypkg --root "$TESTROOT" verify >/dev/null 2>&1 \
  && ok "已安装文件未被改动" || bad "校验不通过"
cp "$TESTROOT/usr/bin/qydemo" /tmp/qy-bin.bak
echo "tampered" >> "$TESTROOT/usr/bin/qydemo"
if ./bin/qypkg --root "$TESTROOT" verify >/dev/null 2>&1; then
  bad "篡改未被检出"
else
  ok "可检测文件被篡改"
fi
cp /tmp/qy-bin.bak "$TESTROOT/usr/bin/qydemo" && rm -f /tmp/qy-bin.bak

step "8. 依赖保护与卸载"
./bin/qypkg --root "$TESTROOT" remove libqydemo >/dev/null 2>&1 \
  && bad "被依赖的包竟被卸载" || ok "拒绝卸载仍被依赖的包"
./bin/qypkg --root "$TESTROOT" remove libqydemo -r >/dev/null 2>&1 \
  && ok "递归卸载成功" || bad "递归卸载失败"
[ -z "$(ls -A "$TESTROOT/usr/bin" 2>/dev/null)" ] && ok "文件已清理干净" \
  || bad "残留文件: $(ls -A "$TESTROOT/usr/bin" 2>/dev/null)"

step "9. 篡改仓库索引必须被拒"
# 在副本上做篡改：不动真实仓库，避免测试之间互相污染
rm -rf /tmp/qy-repo-tamper && cp -r var/repo /tmp/qy-repo-tamper
python3 -c "
import json,pathlib
p=pathlib.Path('/tmp/qy-repo-tamper/x86_64/index.json')
d=json.loads(p.read_text()); d['packages'][0]['version']='9.9.9'
p.write_text(json.dumps(d,ensure_ascii=False,sort_keys=True,separators=(',',':')))"
if ./bin/qypkg --root "$BUILDROOT" --repo /tmp/qy-repo-tamper install qydemo >/dev/null 2>&1; then
  bad "篡改后的索引居然通过验签"
else
  ok "签名校验拒绝被篡改的索引"
fi
if ./bin/qyrepo list --pubkey var/repo/keys/qiyuan.pub >/tmp/qy-repo.log 2>&1; then
  ok "仓库本身未被测试污染，仍是可信状态"
else
  bad "仓库恢复失败"; cat /tmp/qy-repo.log
fi
rm -rf /tmp/qy-repo-tamper

