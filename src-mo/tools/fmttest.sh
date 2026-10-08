#!/bin/bash
# 验证 fmt：格式化只改空白，不改变 token 流。
# 判据：格式化前后编译出的「代码段」必须逐字节相同。
# 这比"程序还能跑"强得多——连一条指令都不能变。
set -e
cd "$(dirname "$0")/.."
MOC=./bin/moc
FMT=/tmp/mofmt.elf
TMP=/tmp/mofmtt
rm -rf $TMP && mkdir -p $TMP

# 编出 fmt 本体（需要标准库在搜索路径上）
mkdir -p $TMP/lib && cp lib/*.mo $TMP/lib/
cp tools/fmt.mo $TMP/fmt.mo
( cd $TMP && $OLDPWD/$MOC fmt.mo out.elf ) || { echo "FAIL: fmt.mo 编译不过"; exit 1; }
cp $TMP/out.elf $FMT && chmod +x $FMT

# 取代码段指纹：offset 176 起，长度取第一个 LOAD 段的 filesz
codesig() {
  python3 -c "
import struct,hashlib,sys
d=open(sys.argv[1],'rb').read()
off,sz=struct.unpack_from('<QQ',d,64+16)
print(hashlib.md5(d[off:off+sz]).hexdigest())
" "$1"
}

FAIL=0
for f in examples/*.mo lib/*.mo tools/fmt.mo; do
  b=$(basename $f)
  cp $f $TMP/$b
  ( cd $TMP && $OLDPWD/$MOC $b a.elf >/dev/null 2>&1 ) || { echo "skip $b (编译需依赖)"; continue; }
  ( cd $TMP && $FMT -w $b ) || { echo "FAIL: fmt 处理 $b 失败"; FAIL=1; continue; }
  ( cd $TMP && $OLDPWD/$MOC $b b.elf >/dev/null 2>&1 ) || { echo "FAIL: 格式化后 $b 编译不过"; FAIL=1; continue; }
  A=$(codesig $TMP/a.elf); B=$(codesig $TMP/b.elf)
  if [ "$A" != "$B" ]; then
    echo "FAIL: $b 格式化后代码段变了"
    echo "  前 $A"
    echo "  后 $B"
    FAIL=1
  fi
done

# 幂等性：格式化两次与一次结果相同
cp examples/freq.mo $TMP/p.mo
( cd $TMP && $FMT p.mo > p1.txt && $FMT -w p.mo && $FMT p.mo > p2.txt )
if ! cmp -s $TMP/p1.txt $TMP/p2.txt; then
  echo "FAIL: 格式化不幂等"; FAIL=1
fi

if [ $FAIL -eq 0 ]; then echo "fmttest: OK（代码段逐字节相同 + 幂等）"; else exit 1; fi
