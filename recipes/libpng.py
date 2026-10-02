"""libpng —— PNG 图像格式库


许可证：zlib-acknowledgement
"""

name = "libpng"
version = "1.6.47"
release = 1
summary = "PNG 图像格式库"
homepage = ""
license = "zlib-acknowledgement"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libpng
source = ["https://download.sourceforge.net/libpng/libpng-1.6.47.tar.xz"]
sha256 = ["b213cb381fbb1175327bd708a77aab708a05adde7b471bc267bd15ac99893631"]

depends = ["zlib"]
makedepends = ["zlib"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
