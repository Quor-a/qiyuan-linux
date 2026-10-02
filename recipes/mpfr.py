"""mpfr —— 多精度浮点运算库（gcc/gawk 依赖）

https://www.mpfr.org
许可证：LGPL-3.0-or-later
"""

name = "mpfr"
version = "4.2.2"
release = 1
summary = "多精度浮点运算库（gcc/gawk 依赖）"
homepage = "https://www.mpfr.org"
license = "LGPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums mpfr
source = ["https://mirrors.aliyun.com/gnu/mpfr/mpfr-4.2.2.tar.gz"]
sha256 = ["826cbb24610bd193f36fde172233fb8c009f3f5c2ad99f644d0dea2e16a20e42"]

depends = ["gmp"]
makedepends = ["gmp"]
provides = ["libmpfr.so.6"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --enable-shared --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
