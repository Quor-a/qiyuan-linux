"""alsa-utils —— ALSA 命令行工具（amixer alsamixer）


许可证：GPL-2.0-or-later
"""

name = "alsa-utils"
version = "1.2.14"
release = 1
summary = "ALSA 命令行工具（amixer alsamixer）"
homepage = ""
license = "GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums alsa-utils
source = ["https://www.alsa-project.org/files/pub/utils/alsa-utils-1.2.14.tar.bz2"]
sha256 = ["0794c74d33fed943e7c50609c13089e409312b6c403d6ae8984fc429c0960741"]

depends = ["alsa-lib", "ncurses"]
makedepends = ["alsa-lib", "ncurses"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-alsaconf --disable-bat")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
