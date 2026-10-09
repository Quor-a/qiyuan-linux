"""libnl —— netlink 协议库

许可证：LGPL-2.1-or-later

iproute2、iw、wpa_supplicant、NetworkManager 都靠它与内核网络栈通信。
没有它，所有这些工具都编不出来——网络管理全废。
"""
from __future__ import annotations

name = "libnl"
version = "3.11"
release = 1
summary = "netlink 协议库（内核网络栈通信）"
homepage = "https://www.infradead.org/~tgr/libnl/"
license = "LGPL-2.1-or-later"

source = ["https://ghproxy.net/https://github.com/thom311/libnl/releases/download/libnl3_11_0/libnl-3.11.0.tar.gz"]
sha256 = ["2a56e1edefa3e68a7c00879496736fdbf62fc94ed3232c0baba127ecfa76874d"]

depends = []
makedepends = ["pkgconf", "flex", "bison"]
provides = ["libnl-3.so.200"]
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
