"""bash —— GNU Bourne-Again Shell（系统默认 shell）

https://www.gnu.org/software/bash
许可证：GPL-3.0-or-later
"""

name = "bash"
version = "5.3"
release = 1
summary = "GNU Bourne-Again Shell（系统默认 shell）"
homepage = "https://www.gnu.org/software/bash"
license = "GPL-3.0-or-later"

source = ["https://mirrors.aliyun.com/gnu/bash/bash-5.3.tar.gz"]
sha256 = ["0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba"]

depends = ["readline", "ncurses"]
makedepends = ["readline", "ncurses"]
provides = ["sh"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --without-bash-malloc --with-installed-readline")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
