"""libxkbfile —— 键盘描述文件解析库


许可证：MIT
"""

name = "libxkbfile"
version = "1.1.3"
release = 1
summary = "键盘描述文件解析库"
homepage = ""
license = "MIT"

source = ["https://www.x.org/releases/individual/lib/libxkbfile-1.1.3.tar.xz"]
sha256 = ["a9b63eea997abb9ee6a8b4fbb515831c841f471af845a09de443b28003874bec"]

depends = ["libX11"]
makedepends = ["libX11"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
