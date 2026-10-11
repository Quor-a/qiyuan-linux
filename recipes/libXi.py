"""libXi —— X 输入扩展库


许可证：MIT
"""

name = "libXi"
version = "1.8.2"
release = 1
summary = "X 输入扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXi
source = ["https://www.x.org/archive/individual/lib/libXi-1.8.2.tar.xz"]
sha256 = ["d0e0555e53d6e2114eabfa44226ba162d2708501a25e18d99cfb35c094c6c104"]

depends = ["libX11", "libXext", "inputproto"]
makedepends = ["libX11", "libXext", "inputproto"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # 交叉时 malloc(0) 运行时测试无法执行——内联 xorg 官方交叉姿势
    cv = "--enable-malloc0returnsnull=yes"
    ctx.run("./configure " + cv + " " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
