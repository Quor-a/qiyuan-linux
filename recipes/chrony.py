"""chrony —— NTP 客户端与服务器


许可证：GPL-2.0-or-later
"""

name = "chrony"
version = "4.6.1"
release = 1
summary = "NTP 客户端与服务器"
homepage = ""
license = "GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums chrony
source = ["https://example.org/src/chrony-4.6.1.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["openssl", "readline"]
makedepends = ["openssl", "readline"]
provides = ["ntp-client"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --sysconfdir=/etc/chrony --with-user=chrony --with-hwclockfile=/etc/adjtime")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
