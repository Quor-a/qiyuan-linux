"""alsa-lib —— ALSA 声音库


许可证：LGPL-2.1-or-later
"""

name = "alsa-lib"
version = "1.2.14"
release = 1
summary = "ALSA 声音库"
homepage = ""
license = "LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums alsa-lib
source = ["https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.14.tar.bz2"]
sha256 = ["be9c88a0b3604367dd74167a2b754a35e142f670292ae47a2fdef27a2ee97a32"]

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
