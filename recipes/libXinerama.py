"""libXinerama —— X 多屏扩展库


许可证：MIT
"""

name = "libXinerama"
version = "1.1.5"
release = 1
summary = "X 多屏扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXinerama
source = ["https://www.x.org/archive/individual/lib/libXinerama-1.1.5.tar.xz"]
sha256 = ["5094d1f0fcc1828cb1696d0d39d9e866ae32520c54d01f618f1a3c1e30c2085c"]

depends = ["libX11", "libXext", "xineramaproto"]
makedepends = ["libX11", "libXext", "xineramaproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
