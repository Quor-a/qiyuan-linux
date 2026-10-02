"""iw —— 无线配置与诊断命令行工具

许可证：ISC

排查无线问题必备：`iw dev`、`iw list` 能直接看出
网卡支持哪些频段、当前关联到哪个 AP、信号强度多少。
没有它，无线故障只能靠猜。
"""
from __future__ import annotations

name = "iw"
version = "6.9"
release = 1
summary = "无线设备配置与诊断工具"
homepage = "https://wireless.wiki.kernel.org/en/users/documentation/iw"
license = "ISC"

source = ["https://git.kernel.org/pub/scm/linux/kernel/git/jberg/iw.git/snapshot/iw-6.9.tar.gz"]
sha256 = ["2554197ec2a28b0e1e8bf0ee816ff66c66e026a0f6735c97d4ef4c36aa7718af"]

depends = ["libnl"]
makedepends = ["pkgconf", "libnl"]
provides = []
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} SBINDIR=/usr/bin install".format(ctx.destdir))
