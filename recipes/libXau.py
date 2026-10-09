"""libXau —— X 授权库


许可证：MIT
"""

name = "libXau"
version = "1.0.12"
release = 1
summary = "X 授权库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXau
source = ["https://www.x.org/archive/individual/lib/libXau-1.0.12.tar.xz"]
sha256 = ["74d0e4dfa3d39ad8939e99bda37f5967aba528211076828464d2777d477fc0fb"]

depends = ["xorgproto"]
makedepends = ["xorg-macros", "xorgproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
