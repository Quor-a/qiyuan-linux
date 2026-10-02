"""glslang —— GLSL 着色器编译器（mesa 构建依赖）


许可证：BSD-3-Clause AND MIT AND Apache-2.0
"""

name = "glslang"
version = "15.1.0"
release = 1
summary = "GLSL 着色器编译器（mesa 构建依赖）"
homepage = ""
license = "BSD-3-Clause AND MIT AND Apache-2.0"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums glslang
source = ["https://example.org/src/glslang-15.1.0.tar.xz"]
sha256 = []
checksum_pending = True

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
