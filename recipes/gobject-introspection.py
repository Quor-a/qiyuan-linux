"""gobject-introspection —— GObject 语言绑定元数据生成器

许可证：LGPL-2.1-or-later AND MIT
"""

name = "gobject-introspection"
version = "1.84.0"
release = 1
summary = "GObject 语言绑定元数据生成器"
license = "LGPL-2.1-or-later AND MIT"

source = ["https://download.gnome.org/sources/gobject-introspection/1.84/gobject-introspection-1.84.0.tar.xz"]
sha256 = ["945b57da7ec262e5c266b89e091d14be800cc424277d82a02872b7d794a84779"]
checksum_pending = True

depends = ["glib"]
makedepends = ["meson", "ninja", "python", "flex", "bison", "glib"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr -Ddoctool=disabled -Dpython=python3.12 --buildtype=release")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
