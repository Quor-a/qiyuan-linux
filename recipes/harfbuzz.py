"""harfbuzz —— 文字塑形引擎（复杂文本排版）

许可证：MIT
"""

name = "harfbuzz"
version = "10.2.0"
release = 1
summary = "文字塑形引擎（复杂文本排版）"
license = "MIT"

source = ["https://github.com/harfbuzz/harfbuzz/archive/refs/tags/10.2.0.tar.gz"]
sha256 = ["11749926914fd488e08e744538f19329332487a6243eec39ef3c63efa154a578"]

depends = ["freetype"]
makedepends = ["meson", "ninja", "freetype"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    nf = cf.replace('qy-cross.ini', 'qy-native.ini') if cf else ""
    x = (f" --cross-file={cf} --native-file={nf}" if cf else "")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr -Dwerror=false -Ddocs=disabled -Dtests=disabled -Dicu=disabled -Dcairo=disabled -Dglib=enabled -Dgobject=enabled -Dintrospection=disabled -Dfreetype=enabled"
            + x)


def package(ctx):
    ctx.run("export PATH=$PATH:{0}/usr/bin; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; cd build && ninja".format(ctx.sysroot))
    ctx.run("export PATH=$PATH:{0}/usr/bin; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && DESTDIR=".format(ctx.sysroot)+str(ctx.destdir)+" ninja install")
