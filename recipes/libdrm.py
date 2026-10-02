"""libdrm —— DRM 内核接口封装库

许可证：MIT
"""

name = "libdrm"
version = "2.4.124"
release = 1
summary = "DRM 内核接口封装库"
license = "MIT"

source = ["https://dri.freedesktop.org/libdrm/libdrm-2.4.125.tar.xz"]
sha256 = ["d4bae92797a50f81a93524762e0410a49cd84cfa0f997795bc0172ac8fb1d96a"]

depends = []
makedepends = ["meson", "ninja"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Dudev=false -Dvalgrind=disabled -Dtests=false")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
