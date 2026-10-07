"""libXfont2 —— X 服务器字体库


许可证：MIT
"""

name = "libXfont2"
version = "2.0.7"
release = 1
summary = "X 服务器字体库"
homepage = ""
license = "MIT"

source = ["https://www.x.org/releases/individual/lib/libXfont2-2.0.7.tar.xz"]
sha256 = ["8b7b82fdeba48769b69433e8e3fbb984a5f6bf368b0d5f47abeec49de3e58efb"]

depends = ["freetype", "fontconfig", "libfontenc", "xorgproto", "xtrans"]
makedepends = ["freetype", "fontconfig", "libfontenc", "xorgproto", "xtrans"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
