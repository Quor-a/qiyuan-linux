"""gdk-pixbuf —— 图像加载库（GTK3 依赖）

许可证：LGPL-2.1-or-later
"""

name = "gdk-pixbuf"
version = "2.42.12"
release = 1
summary = "图像加载库（GTK3 依赖）"
license = "LGPL-2.1-or-later"

source = ["https://download.gnome.org/sources/gdk-pixbuf/2.42/gdk-pixbuf-2.42.12.tar.xz"]
sha256 = ["b9505b3445b9a7e48ced34760c3bcb73e966df3ac94c95a148cb669ab748e3c7"]

depends = ["glib", "libpng", "jpeg-turbo"]
makedepends = ["meson", "ninja", "glib", "gobject-introspection", "libpng", "jpeg-turbo"]

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    cf = ctx.meson_cross_file()
    nf = cf.replace('qy-cross.ini', 'qy-native.ini') if cf else ""
    x = (f" --cross-file={cf} --native-file={nf}" if cf else "")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr " + "-Ddocs=false -Dintrospection=disabled -Dman=false -Dinstalled_tests=false -Dbuiltin_loaders=all -Drelocatable=false" + x)


def package(ctx):
    ctx.run("export PATH=$PATH:{0}/usr/bin; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; ninja -C build".format(ctx.sysroot))
    ctx.run("export PATH=$PATH:{0}/usr/bin; DESTDIR={1} ninja -C build install".format(ctx.sysroot, ctx.destdir))
