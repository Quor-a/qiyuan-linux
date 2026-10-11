"""desktop-file-utils —— .desktop 文件校验与安装工具

许可证：GPL-2.0-or-later
"""

name = "desktop-file-utils"
version = "0.28"
release = 1
summary = ".desktop 文件校验与安装工具"
license = "GPL-2.0-or-later"

source = ["https://www.freedesktop.org/software/desktop-file-utils/releases/desktop-file-utils-0.28.tar.xz"]
sha256 = ["4401d4e231d842c2de8242395a74a395ca468cd96f5f610d822df33594898a70"]

depends = ["glib"]
makedepends = ["meson", "ninja", "glib"]
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
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr " + x + "")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
