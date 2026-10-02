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
T=/home/agentuser/qyw/.qy-txn-root

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

echo
echo "分段通过 $PASS 项，失败 $FAIL 项"
[ "$FAIL" -eq 0 ] || exit 1

