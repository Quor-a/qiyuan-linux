"""desktop-file-utils —— .desktop 文件校验与安装工具

许可证：GPL-2.0-or-later
"""

name = "desktop-file-utils"
version = "0.28"
release = 1
summary = ".desktop 文件校验与安装工具"
license = "GPL-2.0-or-later"

source = ["https://example.org/src/desktop-file-utils-0.28.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["glib"]
makedepends = ["meson", "ninja", "glib"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
