"""gzip —— GNU 压缩工具

https://www.gnu.org/software/gzip
许可证：GPL-3.0-or-later
"""

name = "gzip"
version = "1.13"
release = 1
summary = "GNU 压缩工具"
homepage = "https://www.gnu.org/software/gzip"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums gzip
source = ["https://mirrors.aliyun.com/gnu/gzip/gzip-1.13.tar.gz"]
sha256 = ["20fc818aeebae87cdbf209d35141ad9d3cf312b35a5e6be61bfcfbf9eddd212a"]

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
