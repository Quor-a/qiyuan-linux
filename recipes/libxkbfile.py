"""libxkbfile —— 键盘描述文件解析库


许可证：MIT
"""

name = "libxkbfile"
version = "1.1.3"
release = 1
summary = "键盘描述文件解析库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libxkbfile
source = ["https://example.org/src/libxkbfile-1.1.3.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["libX11"]
makedepends = ["libX11"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
