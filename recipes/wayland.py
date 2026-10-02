"""wayland —— Wayland 显示协议与库

许可证：MIT
"""

name = "wayland"
version = "1.23.1"
release = 1
summary = "Wayland 显示协议与库"
license = "MIT"

source = ["https://gitlab.freedesktop.org/wayland/wayland/-/archive/1.23.1/wayland-1.23.1.tar.gz"]
sha256 = ["158ec49af498f2558c7fbf7e8b070d010d4e270cc6076003a18a6c813f87e244"]

depends = ["libffi", "expat", "libxml2"]
makedepends = ["meson", "ninja", "libffi", "expat", "libxml2"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr --prefix=/usr -Ddocumentation=false")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
