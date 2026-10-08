#!/bin/bash
# 验证 -g 生成的调试信息：readelf 能解出行号表，且行号与源码对得上。
# 另外确认 -g 不影响程序行为（同一程序开与不开 -g 运行结果相同）。
set -e
cd "$(dirname "$0")/.."
MOC=./bin/moc
TMP=/tmp/modbgt
rm -rf $TMP && mkdir -p $TMP

cat > $TMP/d.mo <<'MO'
fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < 10 {
        s = s + fib(i);
        i = i + 1;
    }
    return s;
}
MO

$MOC $TMP/d.mo -g $TMP/d.elf
chmod +x $TMP/d.elf
# 不带 -g 的同名程序，用于比对行为
$MOC $TMP/d.mo $TMP/d0.elf
chmod +x $TMP/d0.elf

A=$($TMP/d.elf; echo $?)
B=$($TMP/d0.elf; echo $?)
if [ "$A" != "88" ]; then echo "FAIL: -g 程序返回 $A，期望 88"; exit 1; fi
if [ "$A" != "$B" ]; then echo "FAIL: -g 与不带 -g 行为不同 ($A vs $B)"; exit 1; fi

# 行号表里应出现源码里的真实行号：3(fib 的 return)、8(s=...)、9(i=i+1)
LINES=$(readelf --debug-dump=decodedline $TMP/d.elf 2>/dev/null | awk 'NF>=4 && $3 ~ /^0x/ {print $2}' | sort -n | uniq)
for want in 8 9; do
  if ! echo "$LINES" | grep -qx "$want"; then
    echo "FAIL: 行号表里缺少行 $want（得到：$(echo $LINES | tr '\n' ' ')）"; exit 1
  fi
done

# 不开 -g 时不应有任何 .debug_* 节
if readelf -SW $TMP/d0.elf 2>/dev/null | grep -q "debug"; then
  echo "FAIL: 不带 -g 时不应生成调试节"; exit 1
fi

echo "dbgtest: OK（-g 行号可用、行为不变、不带 -g 无调试节）"
