"""avahi —— 本地网络服务发现（mDNS/DNS-SD）


许可证：LGPL-2.1-or-later
"""

name = "avahi"
version = "0.8"
release = 1
summary = "本地网络服务发现（mDNS/DNS-SD）"
homepage = ""
license = "LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums avahi
source = ["https://example.org/src/avahi-0.8.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["glib", "dbus", "libdaemon"]
makedepends = ["glib", "dbus", "libdaemon"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static --disable-gtk3 --disable-qt5 --disable-mono --disable-python")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
