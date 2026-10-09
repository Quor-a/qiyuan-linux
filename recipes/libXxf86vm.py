"""XFree86-VidMode 扩展库"""


name = "libXxf86vm"
version = "1.1.6"
release = 1
summary = "XFree86-VidMode 扩展库"
homepage = ""
license = "MIT"

source = ["https://www.x.org/archive/individual/lib/libXxf86vm-1.1.6.tar.xz"]
sha256 = ["96af414c73ce1d5449ad04be7f9f27fa8330f844b6dda843ef22e3e1befb3ee3"]

depends = ["libX11", "libXext", "xorgproto"]
makedepends = ["libX11", "libXext", "xorgproto", "xorg-macros"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
