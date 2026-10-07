"""libarchive —— 多格式归档读写库


许可证：BSD-2-Clause
"""

name = "libarchive"
version = "3.7.8"
release = 1
summary = "多格式归档读写库"
homepage = ""
license = "BSD-2-Clause"

source = ["https://www.libarchive.org/downloads/libarchive-3.7.8.tar.xz"]
sha256 = ["32a51747527e01f50d0e06abad0fe0b95b6fa40b8fc173c48b8bd97d0f743330"]

depends = ["zlib", "xz", "zstd", "openssl", "libxml2"]
makedepends = ["zlib", "xz", "zstd", "openssl", "libxml2"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
