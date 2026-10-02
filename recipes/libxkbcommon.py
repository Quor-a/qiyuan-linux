"""libxkbcommon —— 键盘映射处理库（Wayland 与 X11 共用）

许可证：MIT
"""

name = "libxkbcommon"
version = "1.8.1"
release = 1
summary = "键盘映射处理库（Wayland 与 X11 共用）"
license = "MIT"

source = ["https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-1.8.1.tar.gz"]
sha256 = ["c65c668810db305c4454ba26a10b6d84a96b5469719fe3c729e1c6542b8d0d87"]

depends = ["xorgproto", "libxcb", "libX11", "wayland", "wayland-protocols"]
makedepends = ["bison", "meson", "ninja", "xorgproto", "wayland", "wayland-protocols"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    # 关键：meson 会把 xkb-config-root 解析成构建沙箱的绝对 sysroot 路径，
    # 该路径会被烙进 libxkbcommon.so，装到目标系统后必然找不到键盘数据。
    # 必须显式钉死为 /usr/share/X11/xkb。
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Denable-docs=false -Denable-x11=false "
            "-Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
