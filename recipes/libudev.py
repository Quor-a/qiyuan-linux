"""libudev —— 设备枚举与监控库（eudev，systemd udev 的独立发行版）

许可证：LGPL-2.1-or-later
"""

name = "libudev"
version = "3.2.14"
release = 1
summary = "设备枚举与监控库（eudev 实现）"
homepage = ""
license = "LGPL-2.1-or-later"

source = ["https://github.com/eudev-project/eudev/archive/refs/tags/v3.2.14.tar.gz"]
sha256 = ["c340e6c51dfc5531ac0c0fa84a34b72162acf525f9023eb9cf4931b782c8f177"]

depends = []
makedepends = ["gperf"]
provides = ["libudev.so.1"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # eudev tag 包不带 configure，需 autoreconf（autoconf/automake/libtool 由宿主提供）
    ctx.run("autoreconf -f -i -s")
    ctx.run("./configure --prefix=/usr --disable-static "
            "--disable-manpages --disable-selinux --enable-kmod "
            "--enable-hwdb --disable-introspection "
            "--with-rootlibdir=/usr/lib --with-rootrundir=/run")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
