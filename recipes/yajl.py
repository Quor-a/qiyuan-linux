"""yajl —— JSON 流式解析库（crun 依赖）


许可证：ISC
"""

name = "yajl"
version = "2.1.0"
release = 1
summary = "JSON 流式解析库（crun 依赖）"
homepage = ""
license = "ISC"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums yajl
source = ["https://example.org/src/yajl-2.1.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
