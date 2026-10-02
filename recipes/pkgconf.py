"""pkgconf —— 编译期依赖查询工具（pkg-config 的替代实现）

https://gitea.treehouse.systems/ariadne/pkgconf
许可证：ISC
"""

name = "pkgconf"
version = "2.4.0"
release = 1
summary = "编译期依赖查询工具（pkg-config 的替代实现）"
homepage = "https://gitea.treehouse.systems/ariadne/pkgconf"
license = "ISC"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums pkgconf
source = ["https://distfiles.ariadne.space/pkgconf/pkgconf-2.4.3.tar.xz"]
sha256 = ["51203d99ed573fa7344bf07ca626f10c7cc094e0846ac4aa0023bd0c83c25a41"]

depends = []
makedepends = []
provides = ["pkg-config", "pkgconfig"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --with-pkg-config-dir=/usr/lib/pkgconfig")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
