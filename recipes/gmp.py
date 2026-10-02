"""gmp —— 任意精度算术库

https://gmplib.org
许可证：LGPL-3.0-or-later OR GPL-2.0-or-later
"""

name = "gmp"
version = "6.3.0"
release = 1
summary = "任意精度算术库"
homepage = "https://gmplib.org"
license = "LGPL-3.0-or-later OR GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums gmp
source = ["https://mirrors.aliyun.com/gnu/gmp/gmp-6.3.0.tar.gz"]
sha256 = ["e56fd59d76810932a0555aa15a14b61c16bed66110d3c75cc2ac49ddaa9ab24c"]

depends = []
makedepends = []
provides = ["libgmp.so.10"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --enable-cxx --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
