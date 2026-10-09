"""libelf —— ELF 文件读写库（elfutils 的一部分）

https://sourceware.org/elfutils
许可证：GPL-2.0-or-later AND LGPL-3.0-or-later
"""

name = "libelf"
version = "0.192"
release = 1
summary = "ELF 文件读写库（elfutils 的一部分）"
homepage = "https://sourceware.org/elfutils"
license = "GPL-2.0-or-later AND LGPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libelf
source = ["https://sourceware.org/elfutils/ftp/0.192/elfutils-0.192.tar.bz2"]
sha256 = ["616099beae24aba11f9b63d86ca6cc8d566d968b802391334c91df54eab416b4"]

depends = ["zlib", "zstd"]
makedepends = ["zlib", "zstd"]
provides = ["libelf.so.1"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static --disable-debuginfod")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
