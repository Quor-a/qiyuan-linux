"""texinfo —— Texinfo 文档系统（生成 info 手册）

https://www.gnu.org/software/texinfo
许可证：GPL-3.0-or-later
"""

name = "texinfo"
version = "7.2"
release = 1
summary = "Texinfo 文档系统（生成 info 手册）"
homepage = "https://www.gnu.org/software/texinfo"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums texinfo
source = ["https://mirrors.aliyun.com/gnu/texinfo/texinfo-7.2.tar.gz"]
sha256 = ["e86de7dfef6b352aa1bf647de3a6213d1567c70129eccbf8977706d9c91919c8"]

depends = ["ncurses"]
makedepends = ["perl", "ncurses"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
