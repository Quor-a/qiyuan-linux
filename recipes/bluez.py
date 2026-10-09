"""bluez —— 蓝牙协议栈

许可证：GPL-2.0-or-later AND LGPL-2.1-or-later
"""

name = "bluez"
version = "5.82"
release = 1
summary = "蓝牙协议栈"
license = "GPL-2.0-or-later AND LGPL-2.1-or-later"

source = ["https://cdn.kernel.org/pub/linux/bluetooth/bluez-5.82.tar.xz"]
sha256 = ["0739fa608a837967ee6d5572b43fb89946a938d1c6c26127158aaefd743a790b"]
checksum_pending = False

depends = ["dbus", "glib", "readline", "libudev"]
makedepends = ["meson", "ninja", "dbus", "glib", "readline", "libudev"]
provides = ["bluetooth"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # 上游 5.82 发行包是 autotools（meson 仅 git 主干），按 autotools 构建。
    # sysroot 的 libreadline.so 不带 tinfo 依赖，链接期补 LIBS
    ctx.env("LIBS", "-ltinfow")
    ctx.run("./configure" + " " .join(ctx.configure_args()) + " --prefix=/usr --sysconfdir=/etc --localstatedir=/var "
            "--enable-tools --disable-systemd --enable-experimental "
            "--disable-mesh --disable-manpages --with-udevdir=/usr/lib/udev "
            "--with-dbusconfdir=/etc/dbus-1/system.d")
    ctx.run("make -j2")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
