"""wayland-protocols —— Wayland 标准协议扩展集合

许可证：MIT
"""

name = "wayland-protocols"
version = "1.44"
release = 1
summary = "Wayland 标准协议扩展集合"
license = "MIT"

source = ["https://gitlab.freedesktop.org/wayland/wayland-protocols/-/archive/1.44/wayland-protocols-1.44.tar.gz"]
sha256 = ["a8670a81a92a7108deff767a7b725afaa819b6c5a8b857cba41eac6acba783eb"]

depends = []
makedepends = ["meson", "ninja", "wayland"]
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
    ctx.run('cd build && meson setup .. --prefix=/usr -Dc_args=-Wno-pedantic -Dtests=false' + x)


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
