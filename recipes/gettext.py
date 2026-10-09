"""gettext —— 国际化与本地化工具集

https://www.gnu.org/software/gettext
许可证：GPL-3.0-or-later
"""

name = "gettext"
version = "0.25"
release = 1
summary = "国际化与本地化工具集"
homepage = "https://www.gnu.org/software/gettext"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums gettext
source = ["https://mirrors.aliyun.com/gnu/gettext/gettext-0.25.tar.gz"]
sha256 = ["aee02dab79d9138fdcc7226b67ec985121bce6007edebe30d0e39d42f69a340e"]

depends = ["libxml2", "ncurses"]
makedepends = ["libxml2", "ncurses"]
provides = ["libintl.so.8"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static --docdir=/usr/share/doc/gettext")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
