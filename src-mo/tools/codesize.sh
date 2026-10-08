#!/bin/bash
# 统计各程序的代码段字节数，用于观察代码生成优化的收益
# 用法：tools/codesize.sh [对比用的旧编译器]
OLD="${1:-}"
NEW="${NEW:-$(cd "$(dirname "$0")/.." && pwd)/bin/moc}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

measure() {
  local cc="$1" src="$2"; shift 2
  local w; w="$(mktemp -d)"
  cp "$src" "$w/test.mo"
  for f in "$@"; do cp "$f" "$w/"; done
  ( cd "$w" && "$cc" ) >/dev/null 2>&1
  [ -f "$w/out.elf" ] || { rm -rf "$w"; echo "-"; return; }
  python3 - "$w/out.elf" <<'PY'
import sys, struct
d=open(sys.argv[1],'rb').read()
phoff=struct.unpack_from('<Q',d,0x20)[0]
p_off,p_vaddr=struct.unpack_from('<QQ',d,phoff+8)
# 代码段起点 = 176（ELF头 + 2 个程序头）；末尾补零到 4096，
# 因此取 [176,4096) 里最后一个非零字节作为代码结束位置
region=d[176:4096]
end=len(region)
while end > 0 and region[end-1] == 0:
    end -= 1
print(end)
PY
  rm -rf "$w"
}

printf '%-22s %10s %10s %8s\n' 程序 "${OLD:+优化前}" 当前 缩减
tot_o=0; tot_n=0
for f in "$ROOT"/tests/*.mo; do
  [ "$(basename "$f")" = "run.sh" ] && continue
  n="$(measure "$NEW" "$f")"
  [ "$n" = "-" ] && continue
  if [ -n "$OLD" ]; then
    o="$(measure "$OLD" "$f")"
    tot_o=$((tot_o+o)); tot_n=$((tot_n+n))
    printf '%-22s %10s %10s %7.1f%%\n' "$(basename "$f")" "$o" "$n" "$(python3 -c "print(($o-$n)/$o*100)")"
  fi
done
if [ -n "$OLD" ] && [ "$tot_o" -gt 0 ]; then
  printf '%-22s %10s %10s %7.1f%%\n' 合计 "$tot_o" "$tot_n" "$(python3 -c "print(($tot_o-$tot_n)/$tot_o*100)")"
fi
