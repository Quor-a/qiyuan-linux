"""thermald —— 温度监控与降频保护（手机无风扇，靠降频）

许可证：GPL-2.0-or-later
"""

name = "thermald"
version = "2.5.6"
release = 1
summary = "温度监控与降频保护（手机无风扇，靠降频）"
license = "GPL-2.0-or-later"

source = ["https://example.org/src/thermald-2.5.6.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["dbus", "glib", "libxml2"]
makedepends = ["dbus", "glib", "libxml2"]
provides = ["thermal"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --sysconfdir=/etc")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
