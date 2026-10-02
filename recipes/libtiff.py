"""libtiff —— TIFF 图像格式库


许可证：HPND AND BSD-2-Clause AND MIT
"""

name = "libtiff"
version = "4.7.0"
release = 1
summary = "TIFF 图像格式库"
homepage = ""
license = "HPND AND BSD-2-Clause AND MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libtiff
source = ["https://download.osgeo.org/libtiff/tiff-4.7.0.tar.xz"]
sha256 = ["273a0a73b1f0bed640afee4a5df0337357ced5b53d3d5d1c405b936501f71017"]

depends = ["jpeg-turbo", "zlib", "xz"]
makedepends = ["jpeg-turbo", "zlib", "xz"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
