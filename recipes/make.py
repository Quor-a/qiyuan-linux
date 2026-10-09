"""make —— GNU make 构建工具

https://www.gnu.org/software/make
许可证：GPL-3.0-or-later
"""

name = "make"
version = "4.4.1"
release = 1
summary = "GNU make 构建工具"
homepage = "https://www.gnu.org/software/make"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums make
source = ["https://mirrors.aliyun.com/gnu/make/make-4.4.1.tar.gz"]
sha256 = ["dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3"]

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
