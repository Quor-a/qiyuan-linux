"""json-c —— JSON 解析库


许可证：MIT
"""

name = "json-c"
version = "0.18"
release = 1
summary = "JSON 解析库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums json-c
source = ["https://s3.amazonaws.com/json-c_releases/releases/json-c-0.18.tar.gz"]
sha256 = ["876ab046479166b869afc6896d288183bbc0e5843f141200c677b3e8dfb11724"]
checksum_pending = True

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("mkdir -p build && cd build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DDISABLE_WERROR=ON")
    ctx.run("cd build && make")


def package(ctx):
    ctx.run("cd build && make DESTDIR={} install".format(ctx.destdir))
