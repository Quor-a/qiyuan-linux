"""cairo —— 2D 矢量图形库


许可证：LGPL-2.1-or-later OR MPL-1.1
"""

name = "cairo"
version = "1.18.4"
release = 1
summary = "2D 矢量图形库"
homepage = ""
license = "LGPL-2.1-or-later OR MPL-1.1"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums cairo
source = ["https://cairographics.org/releases/cairo-1.18.4.tar.xz"]
sha256 = ["445ed8208a6e4823de1226a74ca319d3600e83f6369f99b14265006599c32ccb"]

depends = ["pixman", "freetype", "fontconfig", "libpng", "zlib"]
makedepends = ["pixman", "freetype", "fontconfig", "libpng", "zlib", "meson", "ninja"]
provides = ["libcairo.so.2"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("export PATH={0}/usr/bin:$PATH; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && meson setup .. --prefix=/usr -Dtests=disabled -Dglib=enabled".format(ctx.sysroot))


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
