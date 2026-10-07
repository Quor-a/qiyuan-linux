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
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("find . -name hb.hh -exec sed -i 's/#pragma GCC diagnostic error/#pragma GCC diagnostic ignored/' {} +")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("export PATH={0}/usr/bin:$PATH; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && meson setup .. --prefix=/usr -Dwerror=false -Dcpp_args=-Wno-redundant-decls,-Wno-undef,-Wno-error -Ddocs=disabled -Dtests=disabled -Dicu=disabled -Dcairo=disabled -Dglib=disabled -Dgobject=enabled -Dintrospection=enabled -Dfreetype=enabled".format(ctx.sysroot))


def package(ctx):
    ctx.run("export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; cd build && ninja".format(ctx.sysroot))
    ctx.run("export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && DESTDIR=".format(ctx.sysroot)+str(ctx.destdir)+" ninja install")
