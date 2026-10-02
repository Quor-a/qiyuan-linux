"""nghttp2 —— HTTP/2 协议库

许可证：Apache-2.0
"""

name = "nghttp2"
version = "1.65.0"
release = 1
summary = "HTTP/2 协议库"
license = "Apache-2.0"

source = ["https://github.com/nghttp2/nghttp2/releases/download/v1.65.0/nghttp2-1.65.0.tar.gz"]
sha256 = ["8ca4f2a77ba7aac20aca3e3517a2c96cfcf7c6b064ab7d4a0809e7e4e9eb9914"]
checksum_pending = True

depends = ["openssl", "zlib", "libev"]
makedepends = ["openssl", "zlib", "libev"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static --enable-lib-only")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
