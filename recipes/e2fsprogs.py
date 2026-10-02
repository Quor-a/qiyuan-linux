"""e2fsprogs —— ext2/3/4 文件系统工具

http://e2fsprogs.sourceforge.net
许可证：GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause
"""

name = "e2fsprogs"
version = "1.47.3"
release = 1
summary = "ext2/3/4 文件系统工具"
homepage = "http://e2fsprogs.sourceforge.net"
license = "GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums e2fsprogs
source = ["https://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.47.2/e2fsprogs-1.47.2.tar.gz"]
sha256 = ["6dcd67ff9d8b13274ba3f088e4318be4f5b71412cd863524423fc49d39a6371f"]

depends = []
makedepends = []
provides = ["libext2fs.so.2"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --enable-elf-shlibs --disable-libblkid --disable-libuuid --disable-uuidd --disable-fsck")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
