"""cups —— 打印系统


许可证：Apache-2.0 WITH LLVM-exception
"""

name = "cups"
version = "2.4.12"
release = 1
summary = "打印系统"
homepage = ""
license = "Apache-2.0 WITH LLVM-exception"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums cups
source = ["https://example.org/src/cups-2.4.12.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["openssl", "zlib", "libpng", "libtiff", "dbus", "avahi"]
makedepends = ["openssl", "zlib", "libpng", "libtiff", "dbus", "avahi"]
provides = ["printing"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --with-rcdir=/tmp/cupsinit --disable-systemd --with-dbusdir=/usr/share/dbus-1")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
