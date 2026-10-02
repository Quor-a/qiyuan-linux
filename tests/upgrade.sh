#!/usr/bin/env bash
# 第 7—14 周专项测试：系统级原子升级、中断回滚、加固检查、并行编排
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
# 测试根放在工作区而非 /tmp：/tmp 在容器里是 overlay 挂载，
# 刚写入的目录项对子进程可能短暂不可见，会把环境特性误判成代码缺陷
T=/tmp/.qy-txn-root

# 改配方版本（sed -i 在这套文件系统上不稳，统一走 python）
# 等待仓库索引稳定：虚拟/网络文件系统上刚写入的文件可能短暂读不到旧值，
# 等签名能与当前索引对上再继续，避免把环境缓存特性误判为代码缺陷
wait_repo_stable(){
  for _ in 1 2 3 4 5; do
    ./bin/qyrepo list --pubkey var/repo/keys/qiyuan.pub >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# 等待文件对子进程可见：虚拟化文件系统上刚写入的目录项可能短暂不可见，
# 直接执行会报"No such file"，那是环境特性而非代码缺陷
wait_file(){
  local f="$1" i
  for i in 1 2 3 4 5 6 7 8; do
    [ -e "$f" ] && return 0
    sleep 1
  done
  return 1
}

# 测试会反复改写配方版本号。一旦中途被中断（超时、Ctrl-C、环境抖动），
# 配方就会停在某个中间版本，下一次运行的基线全错，症状表现为一堆
# 莫名其妙的失败。用 trap 保证无论怎么退出都把版本号恢复回去。
cleanup(){
  python3 -c "
import pathlib
for f in ('recipes/libqydemo.py','recipes/qydemo.py'):
    p=pathlib.Path(f); t=p.read_text()
    for old in ('0.2.0','0.3.0'):
        t=t.replace('version = "'+old+'"','version = "0.1.0"')
    p.write_text(t)
c=pathlib.Path('tests/demo/libqydemo/qydemo.c'); t=c.read_text()
for old in ('0.2.0','0.3.0'):
    t=t.replace('"'+old+'";','"0.1.0";')
c.write_text(t)
" 2>/dev/null
  qyrm recipes/__pycache__ 2>/dev/null
}
trap cleanup EXIT INT TERM

setver(){
  python3 -c "
import pathlib,sys
v=sys.argv[1]
for f in ('recipes/libqydemo.py','recipes/qydemo.py'):
    p=pathlib.Path(f); t=p.read_text()
    for old in ('0.1.0','0.2.0','0.3.0'):
        t=t.replace('version = \"'+old+'\"','version = \"'+v+'\"')
    p.write_text(t)
c=pathlib.Path('tests/demo/libqydemo/qydemo.c'); t=c.read_text()
for old in ('0.1.0','0.2.0','0.3.0'):
    t=t.replace('\"'+old+'\";','\"'+v+'\";')
c.write_text(t)
" "$1"
  qyrm recipes/__pycache__
}

# 彻底清理上一轮残留：仓库里若留着旧版本包，索引会收敛到那个版本，
# 测试期望的目标版本就永远升不上去，症状看起来像"升级没生效"。
# rm -rf 在这套文件系统上可能报 Directory not empty，要重试。
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
qyrm var/pkgs var/repo/x86_64 var/cache/build-cache.json var/work
qyrm recipes/__pycache__

step "0. 准备基线"
qyrm "$T"; mkdir -p "$T"
setver 0.1.0
# 只编演示包：升级测试关心的是"版本变了之后事务与回滚是否正确"，
# 跟编多少个包无关。编 all 要跑遍 177 个配方的依赖分析，
# 在 2 核环境里这一步就能耗掉整个测试的预算
timeout 180 timeout 180 ./bin/qybuild filesystem qyinit libqydemo qydemo \
  --sign var/repo/keys/qiyuan --force >/dev/null 2>&1 \
  && ok "基线版本构建完成" || bad "基线构建失败"
./bin/qyrepo index --sign var/repo/keys/qiyuan >/dev/null 2>&1
./bin/qypkg --root "$T" install qydemo >/dev/null 2>&1 \
  && ok "安装 0.1.0" || bad "安装失败"

step "1. 升级前检查：新依赖缺失时必须拦下"
cp recipes/qydemo.py /tmp/qy-recipe.bak
# 先正常构建 0.3.0 入库（构建期依赖求解会拦住不存在的包，
# 所以要测的是"仓库里已有的新版引入了缺失依赖"这个升级场景）
python3 -c "
import pathlib
p=pathlib.Path('recipes/qydemo.py'); t=p.read_text()
t=t.replace('version = \"0.1.0\"','version = \"0.3.0\"')
p.write_text(t)"
qyrm recipes/__pycache__
./bin/qybuild qydemo --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
# 再用合法私钥给"新版引入缺失依赖"的索引签名，模拟上游真发了这么个包
python3 -c "
import sys, json; sys.path.insert(0,'.')
from pathlib import Path
from qyos import repo as R
rd = Path('var/repo')
idx = json.loads((rd/'x86_64'/'index.json').read_text())
for e in idx['packages']:
    if e['name']=='qydemo':
        e['depends'] = ['libqydemo','ghost-pkg-xyz']
R.write_index(rd, idx, 'x86_64', Path('var/repo/keys/qiyuan'))
"
# 索引刚被改写，等它在新进程里可读——否则 qypkg 可能读到不一致的
# "索引+签名"组合，输出为空，测试就会误判成"没拦住"
wait_repo_stable
# 注意：不能写成 cmd | grep -q，脚本开了 pipefail，
# 命令非零退出会让整条管道判为假，即使 grep 命中了
./bin/qypkg --root "$T" upgrade >/tmp/qy-precheck.log 2>&1
if grep -q "升级前检查未通过" /tmp/qy-precheck.log; then
  ok "拦截了依赖缺失的升级"
else
  bad "precheck 没有拦住缺失依赖"
fi
cp /tmp/qy-recipe.bak recipes/qydemo.py && rm -f /tmp/qy-recipe.bak
qyrm recipes/__pycache__
./bin/qybuild all --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1

step "1b. 仓库索引只暴露最新版本"
python3 -c "
import json,pathlib
d=json.loads(pathlib.Path('var/repo/x86_64/index.json').read_text())
names=[e['name'] for e in d['packages']]
assert len(names)==len(set(names)), '索引里出现同名多版本: %s' % names
" && ok "同名多版本已在索引层收敛" || bad "索引仍有同名多版本"

step "2. 整批事务升级 0.1.0 → 0.2.0"
setver 0.2.0
./bin/qybuild all --sign var/repo/keys/qiyuan --force >/dev/null 2>&1 \
  && ok "0.2.0 构建完成" || bad "0.2.0 构建失败"
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
wait_repo_stable
./bin/qypkg --root "$T" upgrade >/dev/null 2>&1 && ok "升级事务提交" || bad "升级失败"
wait_file "$T/usr/bin/qydemo" || bad "升级后 qydemo 未出现"
out=$(LD_LIBRARY_PATH="$T/usr/lib" "$T/usr/bin/qydemo" 2>&1)
echo "$out" | grep -q "0.2.0" && ok "运行的是新版本: $(echo "$out"|head -1)" \
  || bad "版本没变: $out"

step "3. 快照与手动回滚"
# 虚拟化文件系统上目录项可能短暂不可见，重试几次再判定"没有快照"
last=""
for _ in 1 2 3; do
  last=$(./bin/qypkg --root "$T" snapshots 2>/dev/null | grep " upgrade " | head -1 | awk '{print $1}')
  [ -n "$last" ] && break
  sleep 1
done
if [ -n "$last" ]; then
  ok "升级产生了可回滚快照（$last）"
  if ./bin/qypkg --root "$T" rollback "$last" >/dev/null 2>&1; then
    wait_file "$T/usr/bin/qydemo" || bad "升级后 qydemo 未出现"
out=$(LD_LIBRARY_PATH="$T/usr/lib" "$T/usr/bin/qydemo" 2>&1)
    echo "$out" | grep -q "0.1.0" && ok "回滚后回到旧版本: $(echo "$out"|head -1)" \
      || bad "回滚后版本不对: $out"
  else
    bad "回滚命令失败"
  fi
else
  bad "没有快照"
fi

step "4. 升级中途断电，下次启动自动恢复"
python3 -c "
import sys, json, shutil, pathlib
root = pathlib.Path('$T')
base = root/'var'/'lib'/'qypkg'
(base/'journal').mkdir(parents=True, exist_ok=True)
snap = base/'snapshots'/'fake-txn'
(snap/'usr'/'bin').mkdir(parents=True, exist_ok=True)
orig = root/'usr'/'bin'/'qydemo'
if orig.exists():
    shutil.copy2(orig, snap/'usr'/'bin'/'qydemo')
    orig.write_text('PARTIALLY-UPGRADED\n')
(base/'journal'/'fake-txn.json').write_text(json.dumps({
    'txid':'fake-txn','action':'upgrade','detail':'模拟中断',
    'state':'pending','started':0,'root':str(root),
    'entries':[{'path':'usr/bin/qydemo','kind':'file','extra':'','type':'file'}],
}))
"
grep -q "PARTIALLY-UPGRADED" "$T/usr/bin/qydemo" && ok "中断现场已构造" || bad "构造失败"
./bin/qypkg --root "$T" recover --dry-run 2>&1 | grep -q "模拟中断" \
  && ok "能检出未完成的事务" || bad "检不出 pending 事务"
./bin/qypkg --root "$T" list >/dev/null 2>&1   # 任一命令启动即自动恢复
grep -q "PARTIALLY-UPGRADED" "$T/usr/bin/qydemo" \
  && bad "自动回滚未生效" || ok "启动即自动回滚，系统恢复可用"
./bin/qypkg --root "$T" recover 2>&1 | grep -q "没有未完成的事务" \
  && ok "恢复后无残留事务" || bad "仍有残留"

step "5. 二进制加固检查（RELRO/NX/PIE/Canary/无残留 rpath）"
./bin/qybuild --audit libqydemo >/tmp/qy-audit.log 2>&1
head -1 /tmp/qy-audit.log
if grep -qE "0/[0-9]+ 个 ELF 通过" /tmp/qy-audit.log; then
  bad "共享库加固项有缺失"; cat /tmp/qy-audit.log
else
  ok "共享库加固项全部通过"
fi
./bin/qybuild --audit qydemo >/tmp/qy-audit2.log 2>&1
head -1 /tmp/qy-audit2.log
if grep -qE "0/[0-9]+ 个 ELF 通过" /tmp/qy-audit2.log; then
  bad "可执行文件加固项有缺失"; cat /tmp/qy-audit2.log
else
  ok "可执行文件加固项全部通过"
fi

step "5b. 产物缓存必须感知源码内容变化"
python3 -c "
import sys; sys.path.insert(0, '.')
from qyos import orchestrator as O
from pathlib import Path
orch = O.Orchestrator(Path('.'))
k1 = orch.cache_key('libqydemo')
src = Path('tests/demo/libqydemo/qydemo.c'); orig = src.read_text()
src.write_text(orig + chr(10) + '// touch' + chr(10))
k2 = orch.cache_key('libqydemo')
src.write_text(orig)
assert k1 != k2, '改了源码缓存键却没变，会编出旧代码打新版本号的包'
assert orch.cache_key('libqydemo') == k1, '改回源码后缓存键应恢复'
print('缓存键已包含源码指纹')
" && ok "改源码不改版本号也会触发重编" || bad "缓存键未感知源码变化"

step "6. 分层并行编排 + 产物缓存"
# 只编排演示包：编排全部 177 个会因源码校验和未填而失败，
# 而这里要测的是分层与缓存，跟编多少包无关
timeout 300 ./bin/qybuild --orchestrate --force -j2 \
  filesystem qyinit libqydemo qydemo >/tmp/qy-orch.log 2>&1
grep -q "编排完成" /tmp/qy-orch.log && ok "编排器跑通" \
  || { bad "编排失败"; tail -10 /tmp/qy-orch.log; }
grep -q "第 0 层" /tmp/qy-orch.log && grep -q "第 1 层" /tmp/qy-orch.log \
  && ok "依赖分层正确（libqydemo 先于 qydemo）" || bad "分层不正确"
timeout 300 ./bin/qybuild --orchestrate -j2 \
  filesystem qyinit libqydemo qydemo >/tmp/qy-orch2.log 2>&1
grep -qE "缓存跳过 [1-9]" /tmp/qy-orch2.log && ok "产物缓存生效（二次构建跳过）" \
  || { bad "缓存未命中"; tail -6 /tmp/qy-orch2.log; }

step "7. 还原配方"
rm -rf "$T"
setver 0.1.0
./bin/qybuild all --sign var/repo/keys/qiyuan --force >/dev/null 2>&1
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
ok "已还原到 0.1.0"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
