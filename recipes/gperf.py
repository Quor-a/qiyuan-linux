"""gperf —— 完美哈希函数生成器（fontconfig 构建依赖）


许可证：GPL-3.0-or-later
"""

name = "gperf"
version = "3.2"
release = 1
summary = "完美哈希函数生成器（fontconfig 构建依赖）"
homepage = ""
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums gperf
source = ["https://mirrors.aliyun.com/gnu/gperf/gperf-3.2.tar.gz"]
sha256 = ["e0ddadebb396906a3e3e4cac2f697c8d6ab92dffa5d365a5bc23c7d41d30ef62"]
checksum_pending = True

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --docdir=/usr/share/doc/gperf")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
