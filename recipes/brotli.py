"""brotli —— Brotli 压缩算法


许可证：MIT
"""

name = "brotli"
version = "1.1.0"
release = 1
summary = "Brotli 压缩算法"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums brotli
source = ["https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz"]
sha256 = ["e720a6ca29428b803f4ad165371771f5398faba397edf6778837a18599ea13ff"]

depends = []
makedepends = ["cmake"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("mkdir -p build")
    ctx.run("cd build && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib")


def package(ctx):
    ctx.run("cd build && make -j2")
    ctx.run("cd build && make DESTDIR={} install".format(ctx.destdir))
