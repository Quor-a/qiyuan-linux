"""pixman —— 像素操作库（cairo 与 X 服务器依赖）


许可证：MIT
"""

name = "pixman"
version = "0.46.2"
release = 1
summary = "像素操作库（cairo 与 X 服务器依赖）"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums pixman
source = ["https://cairographics.org/releases/pixman-0.46.2.tar.xz"]
sha256 = ["d075209d18728b1ca5d0bb864aa047a262a1fde206da8a677d6af75b2ee1ae98"]

depends = []
makedepends = ["meson", "ninja"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr -Dtests=disabled -Dgtk=disabled")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
