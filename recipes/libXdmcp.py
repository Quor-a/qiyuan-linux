"""libXdmcp —— X 显示管理器控制协议库


许可证：MIT
"""

name = "libXdmcp"
version = "1.1.5"
release = 1
summary = "X 显示管理器控制协议库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXdmcp
source = ["https://www.x.org/archive/individual/lib/libXdmcp-1.1.5.tar.xz"]
sha256 = ["d8a5222828c3adab70adf69a5583f1d32eb5ece04304f7f8392b6a353aa2228c"]

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
