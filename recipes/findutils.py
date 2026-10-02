"""findutils —— 文件搜索工具（find xargs locate）

https://www.gnu.org/software/findutils
许可证：GPL-3.0-or-later
"""

name = "findutils"
version = "4.10.0"
release = 1
summary = "文件搜索工具（find xargs locate）"
homepage = "https://www.gnu.org/software/findutils"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums findutils
source = ["https://mirror.math.princeton.edu/pub/gnu/findutils/findutils-4.10.0.tar.xz"]
sha256 = ["1387e0b67ff247d2abde998f90dfbf70c1491391a59ddfecb8ae698789f0a4f5"]

depends = []
makedepends = []
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --localstatedir=/var/lib/locate")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
