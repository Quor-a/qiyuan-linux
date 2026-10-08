"""libsoup —— HTTP 客户端库（GNOME 生态 / WebKit 网络栈）

许可证：LGPL-2.0-or-later
"""

name = "libsoup"
version = "3.6.5"
release = 1
summary = "HTTP 客户端库（GNOME 生态）"
license = "LGPL-2.0-or-later"

source = ["https://download.gnome.org/sources/libsoup/3.6/libsoup-3.6.5.tar.xz"]
sha256 = ["6891765aac3e949017945c3eaebd8cc8216df772456dc9f460976fbdb7ada234"]
checksum_pending = False

depends = ["glib", "libxml2", "sqlite", "openssl", "nghttp2", "brotli", "libpsl"]
makedepends = ["meson", "ninja", "glib", "libxml2", "sqlite", "openssl",
               "nghttp2", "brotli", "libpsl"]
provides = []

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.out_of_tree()
    ctx.run("meson " + str(ctx.srcdir) + " --prefix=/usr -Ddocs=disabled -Dtests=false "
            "-Dvapi=disabled -Dgssapi=disabled -Dsysprof=disabled "
            "-Dautobahn=disabled -Dpkcs11_tests=disabled "
            "-Dc_args=-Wno-error=format-security -Dcpp_args=-Wno-error=format-security")


def package(ctx):
    ctx.run("ninja")
    ctx.run("DESTDIR={} ninja install".format(ctx.destdir))
