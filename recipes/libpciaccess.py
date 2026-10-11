"""libpciaccess —— PCI 设备访问库（xorg-server 依赖）

许可证：MIT
"""

name = "libpciaccess"
version = "0.18.1"
release = 1
summary = "PCI 设备访问库"
license = "MIT"

source = ["https://www.x.org/releases/individual/lib/libpciaccess-0.18.1.tar.xz"]
sha256 = ["4af43444b38adb5545d0ed1c2ce46d9608cc47b31c2387fc5181656765a6fa76"]

depends = []
makedepends = ["meson", "ninja"]
provides = []

requires_build_machine = True

network = False
compression = "xz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    # 0.18 起构建系统从 autotools 换成 meson
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr " + x + "")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
