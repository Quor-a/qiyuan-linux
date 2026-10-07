"""libfontenc —— X 字体编码库（libXfont2 依赖）

许可证：MIT
"""

name = "libfontenc"
version = "1.1.8"
release = 1
summary = "X 字体编码库"
license = "MIT"

source = ["https://www.x.org/releases/individual/lib/libfontenc-1.1.8.tar.xz"]
sha256 = ["7b02c3d405236e0d86806b1de9d6868fe60c313628b38350b032914aa4fd14c6"]

depends = ["zlib"]
makedepends = ["xorg-macros", "zlib"]
provides = []

requires_build_machine = True

network = False
compression = "xz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
