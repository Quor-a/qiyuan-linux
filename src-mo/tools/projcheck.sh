#!/bin/bash
# projcheck —— 项目完整性自检
#
# 背景：这个项目有过好几类「静默漂移」：
#   - src/mo/ 是源、src/compiler.mo 是拼接产物，改了产物没同步回源
#   - 标准库加了函数，测试里却仍引用旧副本
#   - 新库写完了，却没有一个测试引用它
#   - 工具写完了，却没有文档提到它
# 每一类都不是编译错误，而是"看起来能用、实际已经坏了"。
# 这个脚本把它们全部变成**可自动验证的红灯**。
#
#   bash tools/projcheck.sh
set +e
cd "$(dirname "$0")/.."
FAIL=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "=== 1. 编译器源与拼接产物一致 ==="
cat src/mo/compiler_part*.mo > /tmp/pc_join.mo
if diff -q /tmp/pc_join.mo src/compiler.mo >/dev/null; then ok "src/mo/ 拼接 == src/compiler.mo"
else bad "拼接产物与 compiler.mo 不一致（改了 compiler.mo 没同步回 src/mo/）"; fi

echo "=== 2. 每个标准库都能被单独引用 ==="
bash tools/depcheck.sh >/dev/null 2>&1
if [ $? -eq 0 ]; then ok "全部库可独立引用"; else bad "有库缺少自己的 import（见 depcheck）"; fi

echo "=== 3. 每个标准库都有测试覆盖 ==="
MISS=""
for f in lib/*.mo; do
  b=$(basename "$f" .mo)
  if ! grep -rql "\"$b.mo\"" tests/ 2>/dev/null; then MISS="$MISS $b"; fi
done
if [ -z "$MISS" ]; then ok "全部库均有测试引用"
else bad "以下库没有任何测试引用：$MISS"; fi

echo "=== 4. 每个示例都能编译 ==="
BAD=""
for e in examples/*.mo; do
  rm -rf /tmp/pc_ex && mkdir -p /tmp/pc_ex
  cp lib/*.mo /tmp/pc_ex/ 2>/dev/null
  cp "$e" /tmp/pc_ex/test.mo
  ( cd /tmp/pc_ex && timeout 60 "$OLDPWD/bin/moc" >/dev/null 2>&1 ) || BAD="$BAD $(basename $e)"
done
if [ -z "$BAD" ]; then ok "全部示例可编译"
else bad "以下示例编译失败：$BAD"; fi

echo "=== 5. 每个工具都被文档提及 ==="
UN=""
for t in tools/*.sh tools/*.mo; do
  [ -f "$t" ] || continue
  b=$(basename "$t")
  n=${b%.*}
  case "$b" in run.sh) continue;; esac
  if grep -rql "$b" docs/*.md README.md 2>/dev/null; then continue; fi
  if grep -rql "$n" docs/*.md README.md 2>/dev/null; then continue; fi
  UN="$UN $b"
done
if [ -z "$UN" ]; then ok "全部工具有文档"
else bad "以下工具无文档提及：$UN"; fi

echo "=== 6. 文档非空非占位 ==="
SM=""
for f in docs/*.md; do
  n=$(wc -c < "$f")
  if [ "$n" -lt 800 ]; then SM="$SM $(basename $f)($n)"; fi
done
if [ -z "$SM" ]; then ok "全部文档有实质内容"
else bad "以下文档过短（可能是占位）：$SM"; fi

echo "=== 7. 版本号一致 ==="
V=$(cat VERSION)
if grep -q "## \[$V\]" CHANGELOG.md; then ok "VERSION=$V 且 CHANGELOG 有对应条目"
else bad "VERSION=$V 在 CHANGELOG 里没有条目"; fi

echo "=== 8. 无残留脏文件 ==="
JUNK=""
for p in p1.back *.tmp *.bak core *.o *.elf; do
  ls $p >/dev/null 2>&1 && JUNK="$JUNK $p"
done
if [ -z "$JUNK" ]; then ok "仓库无残留产物"
else bad "发现残留文件：$JUNK"; fi

echo
if [ $FAIL -eq 0 ]; then echo "projcheck: OK（8 项全通过）"
else echo "projcheck: $FAIL 项未通过"; exit 1; fi
