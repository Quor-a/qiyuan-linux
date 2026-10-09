"""procps-ng —— 进程与系统状态工具（ps top kill）

https://gitlab.com/procps-ng/procps
许可证：GPL-2.0-or-later AND LGPL-2.1-or-later
"""

name = "procps-ng"
version = "4.0.5"
release = 1
summary = "进程与系统状态工具（ps top kill）"
homepage = "https://gitlab.com/procps-ng/procps"
license = "GPL-2.0-or-later AND LGPL-2.1-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums procps-ng
source = ["https://download.sourceforge.net/procps-ng/procps-ng-4.0.5.tar.xz"]
sha256 = ["c2e6d193cc78f84cd6ddb72aaf6d5c6a9162f0470e5992092057f5ff518562fa"]

depends = ["ncurses"]
makedepends = ["ncurses"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static --disable-kill")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
