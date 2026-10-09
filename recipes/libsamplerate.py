"""libsamplerate —— 采样率转换库


许可证：BSD-2-Clause
"""

name = "libsamplerate"
version = "0.2.2"
release = 1
summary = "采样率转换库"
homepage = ""
license = "BSD-2-Clause"

source = ["https://github.com/libsndfile/libsamplerate/releases/download/0.2.2/libsamplerate-0.2.2.tar.xz"]
sha256 = ["3258da280511d24b49d6b08615bbe824d0cacc9842b0e4caf11c52cf2b043893"]

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
