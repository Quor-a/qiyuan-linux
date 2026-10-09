"""libxml2 —— XML 解析与处理库

https://gitlab.gnome.org/GNOME/libxml2
许可证：MIT
"""

name = "libxml2"
version = "2.14.3"
release = 1
summary = "XML 解析与处理库"
homepage = "https://gitlab.gnome.org/GNOME/libxml2"
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libxml2
source = ["https://download.gnome.org/sources/libxml2/2.13/libxml2-2.13.6.tar.xz"]
sha256 = ["f453480307524968f7a04ec65e64f2a83a825973bcd260a2e7691be82ae70c96"]

depends = ["zlib", "xz"]
makedepends = ["zlib", "xz"]
provides = ["libxml2.so.2"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static --without-python")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
