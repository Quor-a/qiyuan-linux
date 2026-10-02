"""libepoxy —— OpenGL 函数指针管理库

许可证：MIT
"""

name = "libepoxy"
version = "1.5.10"
release = 1
summary = "OpenGL 函数指针管理库"
license = "MIT"

source = ["https://github.com/anholt/libepoxy/archive/refs/tags/1.5.10.tar.gz"]
sha256 = ["a7ced37f4102b745ac86d6a70a9da399cc139ff168ba6b8002b4d8d43c900c15"]

depends = ["mesa"]
makedepends = ["meson", "ninja", "mesa"]
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
