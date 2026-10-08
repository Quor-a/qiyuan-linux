#!/bin/bash
# 墨语言 (Mo) 构建脚本
#   ./build.sh seed        汇编 Stage0 编译器（手写 x86-64 汇编）
#   ./build.sh self [CC]   用 CC 编译 src/compiler.mo（默认 bin/seed）
#   ./build.sh all         seed → self
set -e
cd "$(dirname "$0")"
ROOT=$PWD

seed() {
  echo "== 汇编 Stage0 seed 编译器 =="
  ( cd src/asm && for f in base lex sym expr stmt main; do as -o "$f.o" "$f.s"; done
    ld -o ../../bin/seed base.o lex.o sym.o expr.o stmt.o main.o
    rm -f *.o )
  echo "   -> bin/seed"
}

self() {
  local CC=${1:-bin/seed}
  echo "== 用 $CC 编译 src/compiler.mo =="
  rm -rf /tmp/mobuild && mkdir -p /tmp/mobuild
  cp src/compiler.mo /tmp/mobuild/test.mo
  if [ "$CC" = "bin/seed" ]; then
    ( cd /tmp/mobuild && "$ROOT/bin/seed" test.mo out.elf )
  else
    ( cd /tmp/mobuild && "$ROOT/$CC" )
  fi
  cp /tmp/mobuild/out.elf bin/moc
  echo "   -> bin/moc"
}

case "$1" in
  seed) seed ;;
  self) self "${2:-bin/seed}" ;;
  all)  seed; self bin/seed ;;
  *) echo "用法: $0 {seed|self [编译器]|all}"; exit 1 ;;
esac
