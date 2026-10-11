"""networkmanager —— 网络连接管理服务

许可证：GPL-2.0-or-later AND LGPL-2.1-or-later
"""

name = "networkmanager"
version = "1.52.0"
release = 1
summary = "网络连接管理服务"
license = "GPL-2.0-or-later AND LGPL-2.1-or-later"

source = ["https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/archive/1.52.0/NetworkManager-1.52.0.tar.gz"]
sha256 = ["2ebe60a1497a9650d58336b73413d838189b04543365b3dbc22e1eb8023d205f"]

depends = ["libndp", "libnl", "dbus", "glib", "libudev", "curl", "readline", "openssl", "iwd"]
makedepends = ["libndp", "meson", "ninja", "python", "gobject-introspection", "libnl", "dbus", "glib", "libudev", "curl", "readline", "openssl"]
provides = ["network-manager"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr -Dsession_tracking=false -Dpolkit=false -Dsuspend_resume=consolekit -Dsystemd_journal=false -Ddocs=false -Dqt=false -Dovs=false -Dteamdctl=false -Dwifi=true -Diwd=true -Dppp=false -Dmodem_manager=false -Dselinux=false -Dlibpsl=false -Dnmtui=false -Dnmcli=false -Dtests=false -Dintrospection=false -Dlibaudit=false -Dcrypto=null -Dnm_cloud_setup=false " + x + "")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
