"""wireless-regdb —— 无线频段法规数据库

许可证：ISC

每个国家允许使用的 WiFi 信道和发射功率不同。
没有它内核用最保守的"世界通用"域，结果是：
5GHz 频段大量信道不可用，网速明显低于应有水平——
而且不会有任何错误提示，用户只会觉得"WiFi 很慢"。
"""
from __future__ import annotations

name = "wireless-regdb"
version = "2025.08.07"
release = 1
summary = "无线频段法规数据库（各国信道与功率限制）"
homepage = "https://wireless.wiki.kernel.org/en/developers/regulatory"
license = "ISC"

source = ["https://mirrors.aliyun.com/kernel/software/network/wireless-regdb/wireless-regdb-2025.08.07.tar.xz"]
sha256 = []
checksum_pending = True

depends = []
makedepends = []
provides = ["regdb"]
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    pass


def package(ctx):
    import os
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    # 默认设为 CN：面向中文用户，且不给默认值的话
    # 内核用 "00" 世界域，5GHz 大量信道被禁，网速上不去但不报错
    d = os.path.join(ctx.destdir, "etc", "conf.d")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "wireless-regdom"), "w") as f:
        f.write("WIRELESS_REGDOM=\"CN\"\n")
