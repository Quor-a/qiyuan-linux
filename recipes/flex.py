"""flex —— 词法分析器生成器

https://github.com/westes/flex
许可证：BSD-2-Clause
"""

name = "flex"
version = "2.6.4"
release = 1
summary = "词法分析器生成器"
homepage = "https://github.com/westes/flex"
license = "BSD-2-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums flex
source = ["https://ghproxy.net/https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz"]
sha256 = ["e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995"]

depends = ["m4", "bison"]
makedepends = ["m4", "bison"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --docdir=/usr/share/doc/flex")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
