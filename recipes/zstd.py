"""zstd —— Zstandard 实时压缩算法与库

https://github.com/facebook/zstd
许可证：BSD-3-Clause
"""

name = "zstd"
version = "1.5.7"
release = 1
summary = "Zstandard 实时压缩算法与库"
homepage = "https://github.com/facebook/zstd"
license = "BSD-3-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums zstd
source = ["https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz"]
sha256 = ["eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3"]

depends = ["zlib"]
makedepends = ["zlib"]
provides = ["libzstd.so.1"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("make PREFIX=/usr")


def package(ctx):
    ctx.run("make PREFIX=/usr DESTDIR={} install".format(ctx.destdir))
