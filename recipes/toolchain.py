"""toolchain —— 开发工具链元包（编译器与构建系统）


许可证：Meta
"""

name = "toolchain"
version = "1.0.0"
release = 1
summary = "开发工具链元包（编译器与构建系统）"
homepage = ""
license = "Meta"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums toolchain
source = ["https://example.org/src/toolchain-1.0.0.tar.xz"]
sha256 = []
checksum_pending = True

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
