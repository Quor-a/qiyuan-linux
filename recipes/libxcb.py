"""libxcb —— X C 语言绑定库


许可证：MIT
"""

name = "libxcb"
version = "1.17.0"
release = 1
summary = "X C 语言绑定库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libxcb
source = ["https://www.x.org/archive/individual/xcb/libxcb-1.17.0.tar.xz"]
sha256 = ["599ebf9996710fea71622e6e184f3a8ad5b43d0e5fa8c4e407123c88a59a6d55"]

depends = ["xorgproto", "libXau", "libXdmcp", "xcb-proto"]
makedepends = ["xorg-macros", "python", "xorgproto", "libXau", "libXdmcp", "xcb-proto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --enable-xinput --without-doxygen")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
