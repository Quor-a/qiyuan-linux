"""opus —— Opus 音频编解码库


许可证：BSD-3-Clause
"""

name = "opus"
version = "1.5.2"
release = 1
summary = "Opus 音频编解码库"
homepage = ""
license = "BSD-3-Clause"

source = ["https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz"]
sha256 = ["65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"]

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
