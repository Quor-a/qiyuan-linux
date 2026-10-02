"""python —— Python 语言与运行时

https://www.python.org
许可证：PSF-2.0
"""

name = "python"
version = "3.13.3"
release = 1
summary = "Python 语言与运行时"
homepage = "https://www.python.org"
license = "PSF-2.0"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums python
source = ["https://python.org/ftp/python/3.13.3/Python-3.13.3.tar.xz"]
sha256 = ["40f868bcbdeb8149a3149580bb9bfd407b3321cd48f0be631af955ac92c0e041"]

depends = ["openssl", "zlib", "libffi", "expat", "sqlite", "readline", "ncurses", "xz"]
makedepends = ["coreutils", "openssl", "zlib", "libffi", "expat", "sqlite", "readline", "ncurses", "xz"]
provides = ["python3"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --enable-shared --with-system-expat --with-system-ffi --with-ensurepip=yes --enable-optimizations")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
