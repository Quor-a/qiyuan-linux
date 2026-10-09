"""zlib —— 通用无损数据压缩库

https://zlib.net
许可证：Zlib
"""

name = "zlib"
version = "1.3.1"
release = 1
summary = "通用无损数据压缩库"
homepage = "https://zlib.net"
license = "Zlib"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums zlib
source = ["https://zlib.net/fossils/zlib-1.3.1.tar.gz"]
sha256 = ["9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"]

depends = []
makedepends = []
provides = ["libz.so.1"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # zlib 的 configure 是自己写的，不认 autotools 的 --build/--host，
    # 交叉编译靠环境里的 CC（CrossEnv 已注入），别塞 configure_args。
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
