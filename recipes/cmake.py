"""cmake —— 跨平台构建系统


许可证：BSD-3-Clause
"""

name = "cmake"
version = "3.31.6"
release = 1
summary = "跨平台构建系统"
homepage = ""
license = "BSD-3-Clause"

source = ["https://github.com/Kitware/CMake/archive/refs/tags/v3.31.6.tar.gz"]
sha256 = ["a325dc0566c1421c611dd7507dabd2706419081af8126273dc436d4b1066873c"]

depends = ["curl", "libarchive", "zlib", "expat"]
makedepends = ["openssl", "curl", "libarchive", "zlib", "expat"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --system-curl --system-expat --system-zlib --no-system-jsoncpp --no-system-librhash")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
