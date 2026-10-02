"""sed —— 非交互式流编辑器

https://www.gnu.org/software/sed
许可证：GPL-3.0-or-later
"""

name = "sed"
version = "4.9"
release = 1
summary = "非交互式流编辑器"
homepage = "https://www.gnu.org/software/sed"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums sed
source = ["https://mirrors.aliyun.com/gnu/sed/sed-4.9.tar.gz"]
sha256 = ["d1478a18f033a73ac16822901f6533d30b6be561bcbce46ffd7abce93602282e"]

depends = []
makedepends = []
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --without-selinux")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
