"""giflib —— GIF 图像格式库


许可证：MIT
"""

name = "giflib"
version = "5.2.2"
release = 1
summary = "GIF 图像格式库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums giflib
source = ["https://sourceforge.net/projects/giflib/files/giflib-5.2.2.tar.gz/download"]
sha256 = ["be7ffbd057cadebe2aa144542fd90c6838c6a083b5e8a9048b8ee3b66b29d5fb"]

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("make")


def package(ctx):
    ctx.run("make PREFIX=/usr DESTDIR={} install".format(ctx.destdir))
