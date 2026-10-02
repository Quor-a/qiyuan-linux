"""iproute2 —— 网络配置工具（ip ss tc）

https://wiki.linuxfoundation.org/networking/iproute2
许可证：GPL-2.0-or-later
"""

name = "iproute2"
version = "6.14.0"
release = 1
summary = "网络配置工具（ip ss tc）"
homepage = "https://wiki.linuxfoundation.org/networking/iproute2"
license = "GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums iproute2
source = ["https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-6.12.0.tar.xz"]
sha256 = ["bbd141ef7b5d0127cc2152843ba61f274dc32814fa3e0f13e7d07a080bef53d9"]

depends = ["libelf"]
makedepends = ["bison", "flex", "libelf"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("make PREFIX=/usr")


def package(ctx):
    ctx.run("make PREFIX=/usr DESTDIR={} SBINDIR=/usr/sbin install".format(ctx.destdir))
