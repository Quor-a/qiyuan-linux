"""which —— 定位可执行文件位置

https://savannah.gnu.org/projects/which
许可证：GPL-3.0-or-later
"""

name = "which"
version = "2.23"
release = 1
summary = "定位可执行文件位置"
homepage = "https://savannah.gnu.org/projects/which"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums which
source = ["https://mirrors.aliyun.com/gnu/which/which-2.23.tar.gz"]
sha256 = ["a2c558226fc4d9e4ce331bd2fd3c3f17f955115d2c00e447618a4ef9978a2a73"]

depends = []
makedepends = []
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
