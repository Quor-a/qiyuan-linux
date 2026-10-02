"""libXrender —— X 渲染扩展库


许可证：MIT
"""

name = "libXrender"
version = "0.9.12"
release = 1
summary = "X 渲染扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXrender
source = ["https://www.x.org/archive/individual/lib/libXrender-0.9.12.tar.xz"]
sha256 = ["b832128da48b39c8d608224481743403ad1691bf4e554e4be9c174df171d1b97"]

depends = ["libX11", "renderproto"]
makedepends = ["libX11", "renderproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
