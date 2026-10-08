#!/bin/bash
# cross —— 交叉编译驱动
#
#   ./tools/cross.sh <app.mo> <triplet> [-o out] [-static|-fs]
#
# 原理：墨语言原生后端只会 x86-64 Linux。要到别的架构，走 C 后端：
#      .mo --mo2x c--> .c --交叉编译器--> 目标平台可执行文件
#
# 编译器查找顺序：
#   1) ${TRIPLET}-gcc / ${TRIPLET}-clang
#   2) zig cc -target <triplet>   （apt 装不上时，ziglang 可从 pip 装）
#
# -fs 表示用 freestanding 后端：完全不依赖 libc，系统调用走内联汇编。
#     这是墨语言"零依赖"特性在交叉场景下的自然延伸。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC="$1"; TRIPLET="${2:-aarch64-linux-musl}"; OUT=""
MODE="c"
shift 2 2>/dev/null
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2;;
    -static) MODE="c";;
    -fs) MODE="fs";;
    *) shift;;
  esac
done
case "$SRC" in /*) ;; *) SRC="$ROOT/$SRC";; esac
[ -f "$SRC" ] || { echo "用法: cross.sh <app.mo> <triplet> [-o out] [-fs]"; exit 1; }
[ -x ./bin/mo2x ] || { echo "先编出 bin/mo2x：moc tools/mo2x.mo bin/mo2x"; exit 1; }
[ -z "$OUT" ] && OUT="/tmp/$(basename "$SRC" .mo).$(echo "$TRIPLET" | cut -d- -f1)"

# 选目标后缀
case "$MODE" in
  fs)
    case "$TRIPLET" in
      aarch64*) MO_T="cfs-aarch64";;
      riscv64*) MO_T="cfs-riscv64";;
      *)        MO_T="cfs";;
    esac ;;
  *) MO_T="c" ;;
esac

# 找编译器
CC=""
command -v "${TRIPLET}-gcc"   >/dev/null && CC="${TRIPLET}-gcc"
command -v "${TRIPLET}-clang" >/dev/null && CC="${TRIPLET}-clang"
ZIG=""
python3 -c "import ziglang" >/dev/null 2>&1 && ZIG="python3 -m ziglang"

echo "目标: $TRIPLET   后端: $MO_T"
if [ -z "$CC" ] && [ -z "$ZIG" ]; then
  echo "本机没有交叉编译器。C 源码仍会生成："
  ./bin/mo2x "$SRC" "$MO_T" > "${OUT%.elf}.c" 2>/dev/null
  echo "  -> ${OUT%.elf}.c"
  echo
  echo "可选其一："
  echo "  pip install ziglang          # 推荐：自带全部目标 libc"
  echo "  sudo apt-get install gcc-aarch64-linux-gnu"
  exit 2
fi

./bin/mo2x "$SRC" "$MO_T" > /tmp/mo_cross.c || { echo "转译失败"; exit 1; }

if [ -n "$CC" ]; then
  echo "编译器: $CC"
  $CC -O2 -static -o "$OUT" /tmp/mo_cross.c
else
  echo "编译器: zig cc -target $TRIPLET"
  # freestanding 下 -static 无意义，反而报错
  if [ "$MODE" = "fs" ]; then
    $ZIG cc -target "$TRIPLET" -O2 -o "$OUT" /tmp/mo_cross.c
  else
    case "$TRIPLET" in
      *-musl*|*-freestanding*) $ZIG cc -target "$TRIPLET" -O2 -static -o "$OUT" /tmp/mo_cross.c ;;
      *-linux-gnu*)            $ZIG cc -target "$TRIPLET" -O2 -o "$OUT" /tmp/mo_cross.c ;;
      *)                       $ZIG cc -target "$TRIPLET" -O2 -o "$OUT" /tmp/mo_cross.c ;;
    esac
  fi
fi
if [ $? -ne 0 ]; then echo "编译失败"; exit 1; fi
echo "  -> $OUT"
file "$OUT" 2>/dev/null | cut -c1-120
