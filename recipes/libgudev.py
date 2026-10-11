"""libgudev —— GObject 封装的 udev 客户端库

许可证：LGPL-2.1+
"""

name = "libgudev"
version = "238"
release = 1
summary = "GObject 封装的 udev 客户端库"
license = "LGPL-2.1+"

source = ["https://download.gnome.org/sources/libgudev/238/libgudev-238.tar.xz"]
sha256 = []
checksum_pending = True  # 待首次构建时实测填入，不得预填假哈希

depends = ["glib", "libudev"]
makedepends = ["meson", "ninja", "glib", "libudev"]
provides = ["libgudev-1.0.so.0"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr "
            "-Dtests=false -Dvapi=false -Dintrospection=false" + x)


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
