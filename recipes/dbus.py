"""dbus —— 进程间消息总线（桌面与系统服务通信基础）

许可证：AFL-2.1 OR GPL-2.0-or-later
"""

name = "dbus"
version = "1.16.2"
release = 1
summary = "进程间消息总线（桌面与系统服务通信基础）"
license = "AFL-2.1 OR GPL-2.0-or-later"

source = ["https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz"]
sha256 = ["0ba2a1a4b16afe7bceb2c07e9ce99a8c2c3508e5dec290dbb643384bd6beb7e2"]

depends = ["expat"]
makedepends = ["meson", "ninja", "libX11", "expat"]
provides = ["libdbus-1.so.3"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr --sysconfdir=/etc --localstatedir=/var -Dsystemd=disabled -Dlaunchd=disabled")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
