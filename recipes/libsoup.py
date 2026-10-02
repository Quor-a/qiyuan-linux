"""libsoup —— HTTP 客户端库（GNOME 生态）

许可证：LGPL-2.0-or-later
"""

name = "libsoup"
version = "3.6.5"
release = 1
summary = "HTTP 客户端库（GNOME 生态）"
license = "LGPL-2.0-or-later"

source = ["https://example.org/src/libsoup-3.6.5.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["glib", "libxml2", "sqlite", "openssl", "nghttp2", "brotli"]
makedepends = ["meson", "ninja", "glib", "libxml2", "sqlite", "openssl", "nghttp2", "brotli"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Ddocs=disabled")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
