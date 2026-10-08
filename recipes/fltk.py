"""FLTK —— 轻量 GUI 工具包（Dillo 浏览器依赖）

许可证：LGPL-2.0-or-later（含例外条款）
设计依据：Dillo 需要 fltk-config。本发行版 X11 栈齐备，FLTK 只依赖
  X11/xext/xft/xrender 等，约 2-3 分钟编译完，进基础 ISO 无压力。
"""

name = "fltk"
version = "1.3.9"
release = 1
summary = "轻量 C++ GUI 工具包"
license = "LGPL-2.0-or-later"

source = ["https://fltk.org/pub/fltk/1.3.9/fltk-1.3.9-source.tar.gz"]
sha256 = ["d736b0445c50d607432c03d5ba5e82f3fba2660b10bc1618db8e077a42d9511b"]
checksum_pending = False

depends = ["libX11", "libXext", "libXft", "libXrender", "libXcursor",
           "libXfixes", "libXinerama", "libXrandr", "fontconfig",
           "freetype", "libpng", "zlib", "jpeg-turbo"]
makedepends = ["libX11", "libXext", "libXft", "libXrender", "libXcursor",
               "libXfixes", "libXinerama", "libXrandr", "fontconfig",
               "freetype", "libpng", "zlib", "jpeg-turbo"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # fluid 工具在构建期就要加载 sysroot 的 libjpeg 等动态库。
    # （readline 链接 tinfow 修复后，宿主 awk 不再被 sysroot 库炸掉。）
    ctx.env("LD_LIBRARY_PATH",
            "{0}/usr/lib:{0}/usr/lib/x86_64-linux-gnu:{0}/lib".format(ctx.sysroot))
    ctx.run("./configure --prefix=/usr --enable-shared --enable-xft "
            "--enable-xinerama --enable-xcursor --enable-xfixes "
            "--enable-xdbe --disable-gl "
            "--with-system-libpng --with-system-zlib")


def package(ctx):
    ctx.run("make -j{}".format(ctx.jobs), net=False)
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
