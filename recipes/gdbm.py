"""gdbm —— GNU 数据库例程库

https://www.gnu.org.ua/software/gdbm
许可证：GPL-3.0-or-later
"""

name = "gdbm"
version = "1.25"
release = 1
summary = "GNU 数据库例程库"
homepage = "https://www.gnu.org.ua/software/gdbm"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums gdbm
source = ["https://mirrors.aliyun.com/gnu/gdbm/gdbm-1.25.tar.gz"]
sha256 = ["d02db3c5926ed877f8817b81cd1f92f53ef74ca8c6db543fbba0271b34f393ec"]

depends = ["readline"]
makedepends = ["readline"]
provides = ["libgdbm.so.6"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static --enable-libgdbm-compat")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
