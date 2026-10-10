"""iwd —— 内核原生无线守护（wpa_supplicant 的现代替代）

https://iwd.wiki.kernel.org/
许可证：LGPL-2.1-or-later

比 wpa_supplicant 更省资源、启动更快，且不需要额外加密库
（依赖内核密钥环）。新装机推荐它；老网卡兼容性仍是 wpa_supplicant 更稳，
所以两个都提供，装机时按网卡型号选。
"""
from __future__ import annotations

name = "iwd"
version = "3.9"
release = 1
summary = "内核原生无线守护（iNet Wireless Daemon）"
homepage = "https://iwd.wiki.kernel.org/"
license = "LGPL-2.1-or-later"

source = ["https://www.kernel.org/pub/linux/network/wireless/iwd-3.9.tar.xz"]
sha256 = ["0cd7dc9b32b9d6809a4a5e5d063b5c5fd279f5ad3a0bf03d7799da66df5cad45"]

depends = ["glibc", "readline"]
makedepends = ["pkgconf", "python", "ell", "glibc"]
provides = ["wifi-supplicant"]
conflicts = []
requires_build_machine = True
network = False
compression = "gz"

config_files = ["etc/iwd/main.conf"]


def build(ctx):
    ctx.env("LIBS", "-ltinfow")
    ctx.run("./configure" + " " .join(ctx.configure_args()) + " --prefix=/usr --sysconfdir=/etc"
            " --localstatedir=/var --enable-wired --enable-ofono=no")
    ctx.run("make")


def package(ctx):
    import os
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    d = os.path.join(ctx.destdir, "etc", "iwd")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "main.conf"), "w") as f:
        f.write("""# 由澜岫 Linux 生成
[General]
EnableNetworkConfiguration=true
# 不自动连接所有已知网络：笔记本在多个已知热点之间
# 来回切换会导致网络抖动，且不好排查
AutoConnect=false
[Network]
NameResolvingService=resolvconf
""")
