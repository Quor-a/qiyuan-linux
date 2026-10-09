"""util-linux —— 系统杂项工具（mount lsblk fdisk 等）

https://github.com/util-linux/util-linux
许可证：GPL-2.0-or-later AND BSD-3-Clause AND PublicDomain
"""

name = "util-linux"
version = "2.41"
release = 1
summary = "系统杂项工具（mount lsblk fdisk 等）"
homepage = "https://github.com/util-linux/util-linux"
license = "GPL-2.0-or-later AND BSD-3-Clause AND PublicDomain"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums util-linux
source = ["https://www.kernel.org/pub/linux/utils/util-linux/v2.41/util-linux-2.41.tar.xz"]
sha256 = ["81ee93b3cfdfeb7d7c4090cedeba1d7bbce9141fd0b501b686b3fe475ddca4c6"]

depends = ["zlib", "ncurses"]
makedepends = ["coreutils", "zlib", "ncurses"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static --enable-usrdir-path --without-systemd --without-systemdsystemunitdir --disable-liblastlog2 --without-nvme --disable-schedutils --without-python --disable-makeinstall-chown")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
