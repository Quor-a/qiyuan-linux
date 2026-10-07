"""toolchain —— 开发工具链元包（编译器与构建系统）


许可证：Meta
"""

name = "toolchain"
version = "1.0.0"
release = 1
summary = "开发工具链元包（编译器与构建系统）"
homepage = ""
license = "Meta"

source = []
sha256 = []

depends = ["binutils", "gcc", "make", "pkgconf", "cmake", "meson", "ninja", "patch", "diffutils", "flex", "bison", "m4"]
makedepends = ["binutils", "gcc", "make", "pkgconf", "cmake", "meson", "ninja", "patch", "diffutils", "flex", "bison", "m4"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("mkdir -p {}/usr/share/qiyuan".format(ctx.destdir))
