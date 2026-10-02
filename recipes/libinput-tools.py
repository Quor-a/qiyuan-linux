"""libinput-tools —— 触控与输入设备工具集（移动端元包 touch 的实体）

许可证：MIT
"""

name = "libinput-tools"
version = "1.28.0"
release = 1
summary = "触控与输入设备工具集（移动端元包 touch 的实体）"
license = "MIT"

source = ["https://example.org/src/libinput-tools-1.28.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["libinput", "libevdev", "mtdev"]
makedepends = ["libinput", "libevdev", "mtdev"]
provides = ["touch"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
