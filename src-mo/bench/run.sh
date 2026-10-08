#!/bin/bash
# 性能基准套件：编译 bench/*.mo，各运行一次并记录耗时。
#   bash bench/run.sh            显示本次结果
#   bash bench/run.sh save       把本次结果存为基线 bench/baseline.txt
#   bash bench/run.sh cmp        与基线对比（负数=变快）
set -e
cd "$(dirname "$0")/.."
MOC=./bin/moc
TMP=/tmp/mobench
rm -rf $TMP && mkdir -p $TMP/lib
cp lib/*.mo $TMP/lib/
OUT=""

for f in bench/*.mo; do
  b=$(basename $f .mo)
  cp $f $TMP/t.mo
  ( cd $TMP && $OLDPWD/$MOC t.mo t.elf >/dev/null 2>&1 ) || { echo "FAIL: $b 编译失败"; exit 1; }
  chmod +x $TMP/t.elf
  MS=$(python3 -c "
import subprocess,time,sys
t=time.time(); r=subprocess.run(['$TMP/t.elf'],capture_output=True)
print(int((time.time()-t)*1000), r.returncode)
")
  SET=$(echo $MS | cut -d' ' -f1); RC=$(echo $MS | cut -d' ' -f2)
  OUT="$OUT$b $SET $RC\n"
done

case "${1:-show}" in
  save) printf "$OUT" > bench/baseline.txt; echo "已保存基线:"; printf "$OUT" ;;
  cmp)
    printf "$OUT" | while read name ms rc; do
      base=$(grep "^$name " bench/baseline.txt | awk '{print $2}')
      baserc=$(grep "^$name " bench/baseline.txt | awk '{print $3}')
      d=$((ms - base))
      flag=""
      if [ "$rc" != "$baserc" ]; then flag="  <-- 结果变了!"; fi
      printf "%-8s %6s ms  (基线 %s, %+d ms)%s\n" "$name" "$ms" "$base" "$d" "$flag"
    done ;;
  *) printf "$OUT" | while read name ms rc; do printf "%-8s %6s ms  rc=%s\n" "$name" "$ms" "$rc"; done ;;
esac
