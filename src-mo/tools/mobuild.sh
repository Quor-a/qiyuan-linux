#!/bin/bash
# mobuild —— 墨语言构建脚本
#   用法：mobuild.sh <主文件.mo> [-o 输出名]
#   做三件事：
#     1. 递归收集 import 依赖，按拓扑序输出（人看得见的构建清单）
#     2. 调 moc 编译
#     3. 报出产物大小
#   moc 自己就能递归处理 import，这个脚本的价值在于把依赖图显式打印出来，
#   并给出循环依赖与缺失文件的提前检查。

set -u
ROOT="${MO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MOC="${MOC:-$ROOT/bin/moc}"

src=""
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -h|--help)
      echo "用法: mobuild.sh <主文件.mo> [-o 输出名]"; exit 0 ;;
    *) src="$1"; shift ;;
  esac
done

if [ -z "$src" ]; then
  echo "mobuild: 缺少主文件" >&2
  echo "用法: mobuild.sh <主文件.mo> [-o 输出名]" >&2
  exit 2
fi
if [ ! -f "$src" ]; then
  echo "mobuild: 找不到 $src" >&2
  exit 2
fi

dir="$(cd "$(dirname "$src")" && pwd)"
base="$(basename "$src")"
[ -z "$out" ] && out="${base%.mo}.elf"

# ---------- 递归收集 import ----------
declare -A seen
order=()
missing=0

collect() {
  local f="$1"
  local key
  key="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  [ -n "${seen[$key]:-}" ] && return 0
  seen[$key]=1
  [ -f "$f" ] || { echo "mobuild: 缺失依赖 $f" >&2; missing=1; return 0; }
  order+=("$key")
  # 抽出 import "xxx";
  while IFS= read -r dep; do
    local d
    d="$(dirname "$f")/$dep"
    collect "$d"
  done < <(grep -o 'import[[:space:]]*"[^"]*"' "$f" | sed 's/import[[:space:]]*"//; s/"$//')
}

collect "$dir/$base"
[ "$missing" -ne 0 ] && { echo "mobuild: 依赖缺失，停止" >&2; exit 2; }

echo "mobuild: 主文件 $base"
echo "mobuild: 依赖 $(( ${#order[@]} - 1 )) 个"
for f in "${order[@]}"; do
  printf '  %s\n' "${f#$dir/}"
done

# ---------- 编译 ----------
tmpd="$(mktemp -d)"
cp "$dir/$base" "$tmpd/test.mo"
for f in "${order[@]}"; do
  [ "$f" = "$dir/$base" ] && continue
  cp "$f" "$tmpd/$(basename "$f")" 2>/dev/null
done

( cd "$tmpd" && "$MOC" test.mo prog.elf ) || {
  echo "mobuild: 编译失败" >&2
  rm -rf "$tmpd"
  exit 1
}

mv "$tmpd/prog.elf" "$out"
chmod +x "$out"
rm -rf "$tmpd"

size=$(wc -c < "$out")
echo "mobuild: 输出 $out（${size} 字节）"
