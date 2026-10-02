"""xorg-server —— X.org 显示服务器

许可证：MIT AND X11 AND BSD-3-Clause
"""

name = "xorg-server"
version = "21.1.16"
release = 1
summary = "X.org 显示服务器"
license = "MIT AND X11 AND BSD-3-Clause"

source = ["https://example.org/src/xorg-server-21.1.16.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["pixman", "mesa", "libXfont2", "libxkbfile", "libxshmfence", "libdrm", "libudev", "libinput", "dbus"]
makedepends = ["meson", "ninja", "xorgproto", "flex", "bison", "pixman", "mesa", "libXfont2", "libxkbfile", "libxshmfence", "libdrm", "libudev", "libinput", "dbus"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Dsystemd_logind=false -Dsuid_wrapper=false -Dxvfb=true")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
