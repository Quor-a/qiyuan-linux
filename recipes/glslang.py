"""glslang —— GLSL 着色器编译器（mesa 构建依赖）


许可证：BSD-3-Clause AND MIT AND Apache-2.0
"""

name = "glslang"
version = "15.1.0"
release = 1
summary = "GLSL 着色器编译器（mesa 构建依赖）"
homepage = ""
license = "BSD-3-Clause AND MIT AND Apache-2.0"

source = ["https://github.com/KhronosGroup/glslang/archive/refs/tags/15.1.0.tar.gz"]
sha256 = ["4bdcd8cdb330313f0d4deed7be527b0ac1c115ff272e492853a6e98add61b4bc"]

depends = []
makedepends = ["cmake", "ninja", "python"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release .")
    ctx.run("ninja")


def package(ctx):
    ctx.run("ninja install")
