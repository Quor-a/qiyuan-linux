"""xkeyboard-config —— X 键盘布局数据（libxkbcommon/weston 依赖）"""

name = "xkeyboard-config"
version = "2.44"
release = 1
summary = "X keyboard 布局/符号表数据"
homepage = "https://www.freedesktop.org/wiki/Software/XKeyboardConfig/"
license = "MIT"

source = ["https://www.x.org/archive/individual/data/xkeyboard-config/xkeyboard-config-2.44.tar.xz"]
sha256 = ["54d2c33eeebb031d48fa590c543e54c9bcbd0f00386ebc6489b2f47a0da4342a"]

depends = []
makedepends = []
requires_build_machine = False


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --buildtype=release " + x + "")
    ctx.run("cd build && ninja")
    ctx.run("cd build && meson install --destdir {}".format(ctx.destdir))


def package(ctx):
    pass
