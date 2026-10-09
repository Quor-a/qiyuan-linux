"""tar —— 归档工具

https://www.gnu.org/software/tar
许可证：GPL-3.0-or-later
"""

name = "tar"
version = "1.35"
release = 1
summary = "归档工具"
homepage = "https://www.gnu.org/software/tar"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums tar
source = ["https://mirrors.aliyun.com/gnu/tar/tar-1.35.tar.gz"]
sha256 = ["14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e"]

depends = ["zlib", "zstd"]
makedepends = ["zlib", "zstd"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --without-selinux --without-posix-acls --without-capabilities")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
