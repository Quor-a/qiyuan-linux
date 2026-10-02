"""bison —— GNU 语法分析器生成器

https://www.gnu.org/software/bison
许可证：GPL-3.0-or-later
"""

name = "bison"
version = "3.8.2"
release = 1
summary = "GNU 语法分析器生成器"
homepage = "https://www.gnu.org/software/bison"
license = "GPL-3.0-or-later"

source = ["https://mirrors.aliyun.com/gnu/bison/bison-3.8.2.tar.xz"]
sha256 = ["9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2"]

depends = ["m4"]
makedepends = ["m4"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --docdir=/usr/share/doc/bison")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
