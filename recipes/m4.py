"""m4 —— GNU 宏处理器（autotools 依赖）

https://www.gnu.org/software/m4
许可证：GPL-3.0-or-later
"""

name = "m4"
version = "1.4.20"
release = 1
summary = "GNU 宏处理器（autotools 依赖）"
homepage = "https://www.gnu.org/software/m4"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums m4
source = ["https://mirrors.aliyun.com/gnu/m4/m4-1.4.20.tar.gz"]
sha256 = ["6ac4fc31ce440debe63987c2ebbf9d7b6634e67a7c3279257dc7361de8bdb3ef"]

depends = []
makedepends = []
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
