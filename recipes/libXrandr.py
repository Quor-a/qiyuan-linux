"""libXrandr —— X 屏幕分辨率与旋转扩展库


许可证：MIT
"""

name = "libXrandr"
version = "1.5.4"
release = 1
summary = "X 屏幕分辨率与旋转扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXrandr
source = ["https://www.x.org/archive/individual/lib/libXrandr-1.5.4.tar.xz"]
sha256 = ["1ad5b065375f4a85915aa60611cc6407c060492a214d7f9daf214be752c3b4d3"]

depends = ["libX11", "libXext", "libXrender", "randrproto"]
makedepends = ["libX11", "libXext", "libXrender", "randrproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
