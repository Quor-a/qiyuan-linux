"""libXdamage —— X 损坏区域扩展库


许可证：MIT
"""

name = "libXdamage"
version = "1.1.6"
release = 1
summary = "X 损坏区域扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXdamage
source = ["https://www.x.org/archive/individual/lib/libXdamage-1.1.6.tar.xz"]
sha256 = ["52733c1f5262fca35f64e7d5060c6fcd81a880ba8e1e65c9621cf0727afb5d11"]

depends = ["libX11", "libXfixes", "damageproto"]
makedepends = ["libX11", "libXfixes", "damageproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
