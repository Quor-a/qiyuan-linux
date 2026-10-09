"""libvorbis —— Vorbis 音频编解码库


许可证：BSD-3-Clause
"""

name = "libvorbis"
version = "1.3.7"
release = 1
summary = "Vorbis 音频编解码库"
homepage = ""
license = "BSD-3-Clause"

source = ["https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz"]
sha256 = ["b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b"]

depends = ["libogg"]
makedepends = ["libogg"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
