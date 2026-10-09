"""flac —— 无损音频编解码器


许可证：GPL-2.0-or-later AND BSD-3-Clause
"""

name = "flac"
version = "1.5.0"
release = 1
summary = "无损音频编解码器"
homepage = ""
license = "GPL-2.0-or-later AND BSD-3-Clause"

source = ["https://downloads.xiph.org/releases/flac/flac-1.5.0.tar.xz"]
sha256 = ["f2c1c76592a82ffff8413ba3c4a1299b6c7ab06c734dee03fd88630485c2b920"]

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
