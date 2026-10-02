"""readline —— 命令行行编辑与历史库

https://tiswww.case.edu/php/chet/readline/rltop.html
许可证：GPL-3.0-or-later
"""

name = "readline"
version = "8.2"
release = 1
summary = "命令行行编辑与历史库"
homepage = "https://tiswww.case.edu/php/chet/readline/rltop.html"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums readline
source = ["https://mirrors.aliyun.com/gnu/readline/readline-8.2.tar.gz"]
sha256 = ["3feb7171f16a84ee82ca18a36d7b9be109a52c04f492a053331d7d1095007c35"]

depends = ["ncurses"]
makedepends = ["ncurses"]
provides = ["libreadline.so.8"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
