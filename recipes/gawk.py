"""gawk —— GNU awk 文本处理语言

https://www.gnu.org/software/gawk
许可证：GPL-3.0-or-later
"""

name = "gawk"
version = "5.3.1"
release = 1
summary = "GNU awk 文本处理语言"
homepage = "https://www.gnu.org/software/gawk"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums gawk
source = ["https://mirrors.aliyun.com/gnu/gawk/gawk-5.3.1.tar.gz"]
sha256 = ["fa41b3a85413af87fb5e3a7d9c8fa8d4a20728c67651185bb49c38a7f9382b1e"]

depends = ["readline", "mpfr"]
makedepends = ["readline", "mpfr"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # gawk 会自动检测并链接 libtinfo（termcap 接口）。sysroot 的 widec ncurses
    # 提供的是 libtinfow，直接指给 configure，避免运行期找不到 libtinfo.so.6
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --with-libtinfo=-lncursesw")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
