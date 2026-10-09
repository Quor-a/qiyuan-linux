"""libXcomposite —— X 合成扩展库


许可证：MIT
"""

name = "libXcomposite"
version = "0.4.6"
release = 1
summary = "X 合成扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXcomposite
source = ["https://www.x.org/archive/individual/lib/libXcomposite-0.4.6.tar.xz"]
sha256 = ["fe40bcf0ae1a09070eba24088a5eb9810efe57453779ec1e20a55080c6dc2c87"]

depends = ["libX11", "libXfixes", "compositeproto"]
makedepends = ["libX11", "libXfixes", "compositeproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
