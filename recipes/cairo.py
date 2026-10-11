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

depends = ["pixman", "freetype", "fontconfig", "libpng", "zlib", "glib"]
makedepends = ["pixman", "freetype", "fontconfig", "libpng", "zlib", "glib", "meson", "ninja"]
provides = ["libcairo.so.2"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("export PATH=$PATH:{0}/usr/bin; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && meson setup .. --prefix=/usr -Dtests=disabled -Dglib=enabled".format(ctx.sysroot) + x)


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
    # pango 的 introspection include 需要 cairo-1.0.gir；meson 的
    # -Dgir=... 在 cairo 上游默认不开（且依赖 g-ir-scanner），
    # 这里直接手写最小 gir（cgo 封装层，g-ir-scanner 只解析 include 名）。
    import shutil
    if shutil.which("g-ir-scanner") is None:
        return
    gir = ctx.destdir / "usr" / "share" / "gir-1.0"
    gir.mkdir(parents=True, exist_ok=True)
    (gir / "cairo-1.0.gir").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<repository version="1.2"\n'
        '            xmlns="http://www.gtk.org/introspection/core/1.0"\n'
        '            xmlns:c="http://www.gtk.org/introspection/c/1.0"\n'
        '            xmlns:glib="http://www.gtk.org/introspection/glib/1.0">\n'
        '  <include name="GLib" version="2.0"/>\n'
        '  <namespace name="cairo" version="1.0"\n'
        '             c:identifier-prefixes="cairo"\n'
        '             c:symbol-prefixes="cairo"/>\n'
        '</repository>\n')
