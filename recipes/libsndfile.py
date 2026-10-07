"""libsndfile —— 音频文件读写库


许可证：LGPL-2.1-or-later
"""

name = "libsndfile"
version = "1.2.2"
release = 1
summary = "音频文件读写库"
homepage = ""
license = "LGPL-2.1-or-later"

source = ["https://github.com/libsndfile/libsndfile/releases/download/1.2.2/libsndfile-1.2.2.tar.xz"]
sha256 = ["3799ca9924d3125038880367bf1468e53a1b7e3686a934f098b7e1d286cdb80e"]

depends = ["libsamplerate", "flac", "libogg", "libvorbis", "opus"]
makedepends = ["libsamplerate", "flac", "libogg", "libvorbis", "opus"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
