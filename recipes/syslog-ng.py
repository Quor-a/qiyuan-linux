"""syslog-ng —— 系统日志守护进程


许可证：LGPL-2.1-or-later AND GPL-2.0-or-later
"""

name = "syslog-ng"
version = "4.9.0"
release = 1
summary = "系统日志守护进程"
homepage = ""
license = "LGPL-2.1-or-later AND GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums syslog-ng
source = ["https://example.org/src/syslog-ng-4.9.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["glib", "openssl", "pcre2", "json-c"]
makedepends = ["glib", "openssl", "pcre2", "json-c"]
provides = ["log-daemon"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --sysconfdir=/etc --enable-json --disable-java --disable-java-modules")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
