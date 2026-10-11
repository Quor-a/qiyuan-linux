"""libinput —— 输入设备处理库

许可证：MIT
"""

name = "libinput"
version = "1.28.0"
release = 1
summary = "输入设备处理库"
license = "MIT"

source = ["https://gitlab.freedesktop.org/libinput/libinput/-/archive/1.27.1/libinput-1.27.1.tar.gz"]
sha256 = ["f6d623dd8230db337a6457645ebca96b9d4788a56385463bb14b8174910dfe23"]

depends = ["libevdev", "mtdev", "libudev"]
makedepends = ["meson", "ninja", "libevdev", "mtdev", "libudev"]
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
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Dtests=false -Ddocumentation=false -Dlibwacom=false -Ddebug-gui=false -Dinstall-tests=false " + x + "")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
