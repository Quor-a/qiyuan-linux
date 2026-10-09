"""libXfixes —— X 修正扩展库


许可证：MIT
"""

name = "libXfixes"
version = "6.0.1"
release = 1
summary = "X 修正扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXfixes
source = ["https://www.x.org/archive/individual/lib/libXfixes-6.0.1.tar.xz"]
sha256 = ["b695f93cd2499421ab02d22744458e650ccc88c1d4c8130d60200213abc02d58"]

depends = ["libX11", "fixesproto"]
makedepends = ["libX11", "fixesproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
