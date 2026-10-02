"""xz —— XZ / LZMA 压缩工具与库

https://tukaani.org/xz
许可证：GPL-2.0-or-later AND PublicDomain
"""

name = "xz"
version = "5.8.1"
release = 1
summary = "XZ / LZMA 压缩工具与库"
homepage = "https://tukaani.org/xz"
license = "GPL-2.0-or-later AND PublicDomain"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums xz
source = ["https://ghproxy.net/https://github.com/tukaani-project/xz/releases/download/v5.8.1/xz-5.8.1.tar.gz"]
sha256 = ["507825b599356c10dca1cd720c9d0d0c9d5400b9de300af00e4d1ea150795543"]

depends = []
makedepends = []
provides = ["liblzma.so.5"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/xz")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
