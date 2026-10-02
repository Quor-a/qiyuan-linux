"""ninja —— 小型高速构建工具


许可证：Apache-2.0
"""

name = "ninja"
version = "1.12.1"
release = 1
summary = "小型高速构建工具"
homepage = ""
license = "Apache-2.0"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums ninja
source = ["https://github.com/ninja-build/ninja/archive/refs/tags/v1.12.1.tar.gz"]
sha256 = ["821bdff48a3f683bc4bb3b6f0b5fe7b2d647cf65d52aeb63328c91a6c6df285a"]
checksum_pending = True

depends = []
makedepends = ["python"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("python3 configure.py --bootstrap")


def package(ctx):
    ctx.run("install -Dm755 ninja {}/usr/bin/ninja".format(ctx.destdir))
