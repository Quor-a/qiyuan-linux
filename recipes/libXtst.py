"""libXtst —— X 测试扩展库（自动化测试依赖）


许可证：MIT
"""

name = "libXtst"
version = "1.2.5"
release = 1
summary = "X 测试扩展库（自动化测试依赖）"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXtst
source = ["https://example.org/src/libXtst-1.2.5.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["libX11", "libXi", "libXext"]
makedepends = ["libX11", "libXi", "libXext"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
