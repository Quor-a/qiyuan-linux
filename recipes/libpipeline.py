"""libpipeline —— 子进程管道管理库（man-db 依赖）

https://gitlab.freedesktop.org/bwidawsk/libpipeline
许可证：GPL-3.0-or-later
"""

name = "libpipeline"
version = "1.5.8"
release = 1
summary = "子进程管道管理库（man-db 依赖）"
homepage = "https://gitlab.freedesktop.org/bwidawsk/libpipeline"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libpipeline
source = ["https://download.savannah.gnu.org/releases/libpipeline/libpipeline-1.5.8.tar.gz"]
sha256 = ["1b1203ca152ccd63983c3f2112f7fe6fa5afd453218ede5153d1b31e11bb8405"]

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
