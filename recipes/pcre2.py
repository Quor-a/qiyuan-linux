"""pcre2 —— Perl 兼容正则表达式库

https://www.pcre.org
许可证：BSD-3-Clause
"""

name = "pcre2"
version = "10.45"
release = 1
summary = "Perl 兼容正则表达式库"
homepage = "https://www.pcre.org"
license = "BSD-3-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums pcre2
source = ["https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.45/pcre2-10.45.tar.bz2"]
sha256 = ["21547f3516120c75597e5b30a992e27a592a31950b5140e7b8bfde3f192033c4"]

depends = []
makedepends = []
provides = ["libpcre2-8.so.0"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --enable-pcre2-16 --enable-pcre2-32 --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
