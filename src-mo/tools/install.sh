#!/bin/bash
# 墨语言安装器：把 moc / mo / 标准库 装到指定前缀
#   ./tools/install.sh           装到 ~/.local
#   PREFIX=/usr/local ./tools/install.sh
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
PREFIX="${PREFIX:-$HOME/.local}"

[ -x "$ROOT/bin/moc" ] || { echo "先跑 make 编出 bin/moc"; exit 1; }

echo "安装到 $PREFIX"
mkdir -p "$PREFIX/bin" "$PREFIX/lib/mo"

install -m 755 "$ROOT/bin/moc"   "$PREFIX/bin/moc"
[ -x "$ROOT/bin/mo2c" ] && install -m 755 "$ROOT/bin/mo2c" "$PREFIX/bin/mo2c"
install -m 755 "$ROOT/tools/mo.sh" "$PREFIX/bin/mo"
cp "$ROOT"/lib/*.mo "$PREFIX/lib/mo/"

# mo.sh 会按自身位置找仓库根目录；装到 bin 下后改为靠 lib/mo 找标准库，
# 因此这里额外写一个精简 wrapper
cat > "$PREFIX/bin/mo" <<'WRAP'
#!/bin/bash
# 墨语言命令行（安装版）
LIBMO="$(dirname "$(readlink -f "$0")")/../lib/mo"
case "${1:-}" in
  version) echo "installed"; exit 0 ;;
  "") echo "用法: mo {build|run|fmt|info|version}"; exit 1 ;;
esac
exec "$(dirname "$(readlink -f "$0")")/moc" "$@"
WRAP
chmod 755 "$PREFIX/bin/mo"

echo "  $PREFIX/bin/moc"
echo "  $PREFIX/bin/mo"
echo "  $PREFIX/lib/mo/*.mo"
echo
echo "提示：把 $PREFIX/bin 加进 PATH"
