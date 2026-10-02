"""inetutils —— 基础网络客户端与服务端（ftp telnet）

https://www.gnu.org/software/inetutils
许可证：GPL-3.0-or-later
"""

name = "inetutils"
version = "2.6"
release = 1
summary = "基础网络客户端与服务端（ftp telnet）"
homepage = "https://www.gnu.org/software/inetutils"
license = "GPL-3.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums inetutils
source = ["https://mirrors.aliyun.com/gnu/inetutils/inetutils-2.6.tar.gz"]
sha256 = ["ccaa256e0d646df7f285ff158a3291f37cd1fc8382f3774d22f7254127635da7"]

depends = ["readline", "ncurses"]
makedepends = ["readline", "ncurses"]
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --disable-talk --disable-ftp --disable-ftpd --disable-servers")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
