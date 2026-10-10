#!/bin/bash
# prepare-build-host.sh — 构建机准备（幂等，可在任意构建机重跑）
#
# 为什么需要这个脚本：澜岫的构建环境把 sysroot 里的 .pc 文件通过
# PKG_CONFIG_SYSROOT_DIR 前缀成 sysroot 路径。当某个重包（如
# gobject-introspection）**尚未自举、暂由宿主提供**时，宿主 .pc 里的
# 工具变量也会被前缀，于是
#   /usr/bin/x86_64-linux-gnu-g-ir-scanner
# 被改写成
#   $SYSROOT/usr/bin/x86_64-linux-gnu-g-ir-scanner
# 这个路径并不存在，meson 判定 "tool variable contains erroneous value"
# 直接报错——表现上像是配方写错，实际上是构建机缺一个同名软链。
#
# 因此：宿主上装 g-i 后，必须在 sysroot 里放同名软链，指向宿主工具。
# 这不是"污染 sysroot"：sysroot 本就是构建期环境，gcc/glibc 本来就由宿主提供。
set -e

Q="${Q:-$(cd "$(dirname "$0")/.." && pwd)}"
SYSROOT="$Q/var/sysroot"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "缺少宿主工具: $1"; MISSING=1; }; }

echo "== 检查宿主构建工具 =="
MISSING=0
for t in gcc make pkg-config meson ninja bison flex autoconf automake libtoolize \
         gperf gettext g-ir-scanner cmake; do
  need "$t"
done
# 内核 objtool 需要 gelf.h（libelf-dev）；mesa 需要 llvm pkgconfig
[ -f /usr/include/gelf.h ] || { echo "缺少头文件: gelf.h (libelf-dev)"; MISSING=1; }
# man-db 构建用宿主 groff 生成自身手册页（troff -me 宏）
command -v groff >/dev/null || { echo "缺少工具: groff"; MISSING=1; }
[ "$MISSING" = 0 ] || {
  echo
  echo "在 Debian/Ubuntu 上执行："
  echo "  sudo apt-get install -y build-essential pkg-config bison flex autoconf automake libtool \\"
  echo "       gperf gettext gobject-introspection libglib2.0-dev-bin llvm-dev libelf-dev"
  echo "  # meson/ninja 若宿主仓库过旧，用 uv 装："
  echo "  uv venv ~/.venvs/qybuild && VIRTUAL_ENV=~/.venvs/qybuild uv pip install meson ninja"
  echo "  sudo ln -sf ~/.venvs/qybuild/bin/meson /usr/local/bin/meson"
  echo "  sudo ln -sf ~/.venvs/qybuild/bin/ninja /usr/local/bin/ninja"
  exit 1
}

echo "== 安装 sysroot 工具软链（重包暂由宿主提供时必需）=="
mkdir -p "$SYSROOT/usr/bin"
# g-i 的 .pc 用 multiarch 名，必须在 sysroot 里同名可见
if command -v g-ir-scanner >/dev/null 2>&1; then
  for tool in g-ir-scanner g-ir-compiler g-ir-generate; do
    command -v "$tool" >/dev/null 2>&1 || continue
    ln -sf "$(command -v "$tool")" "$SYSROOT/usr/bin/$tool"
    ln -sf "$(command -v "$tool")" "$SYSROOT/usr/bin/x86_64-linux-gnu-$tool"
    echo "  $tool -> $SYSROOT/usr/bin/"
  done
  # g-ir-scanner 运行时还要读 share/gobject-introspection-1.0/gdump.c
  # （PKG_CONFIG_SYSROOT_DIR 把路径前缀成 sysroot）。
  if [ -d /usr/share/gobject-introspection-1.0 ]; then
    mkdir -p "$SYSROOT/usr/share/gobject-introspection-1.0"
    cp -a /usr/share/gobject-introspection-1.0/. \
          "$SYSROOT/usr/share/gobject-introspection-1.0/" 2>/dev/null || true
    echo "  gdump.c 等 share 数据 -> $SYSROOT/usr/share/gobject-introspection-1.0/"
  fi
fi
# llvm 同理：mesa 用 -Dllvm=enabled，需要 llvm.pc 可见
if [ -d /usr/lib/llvm-18/lib/pkgconfig ]; then
  :
elif [ -x /usr/lib/llvm-18/bin/llvm-config ]; then
  mkdir -p /tmp/qy-llvm-pc
  cat > /tmp/qy-llvm-pc/llvm.pc <<EOF
prefix=/usr/lib/llvm-18
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LLVM
Description: Low-Level Virtual Machine (构建机提供)
Version: $(/usr/lib/llvm-18/bin/llvm-config --version)
Libs: -L\${libdir} -lLLVM-18
Cflags: -I\${includedir}
EOF
  sudo mkdir -p /usr/lib/llvm-18/lib/pkgconfig
  sudo cp /tmp/qy-llvm-pc/llvm.pc /usr/lib/llvm-18/lib/pkgconfig/llvm.pc
  echo "  已补 llvm.pc（宿主 llvm-dev 未提供时）"
fi

echo "OCHAIN-OK 构建机准备完成"
