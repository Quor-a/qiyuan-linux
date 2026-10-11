"""libevdev —— 输入事件设备封装库

许可证：MIT
"""

name = "libevdev"
version = "1.13.1"
release = 1
summary = "输入事件设备封装库"
license = "MIT"

source = ["https://www.freedesktop.org/software/libevdev/libevdev-1.13.4.tar.xz"]
sha256 = ["f00ab8d42ad8b905296fab67e13b871f1a424839331516642100f82ad88127cd"]

depends = []
makedepends = ["meson", "ninja"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Dtests=disabled -Ddocumentation=disabled " + x + "")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
