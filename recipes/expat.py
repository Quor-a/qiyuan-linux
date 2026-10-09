"""expat —— 流式 XML 解析库

https://libexpat.github.io
许可证：MIT
"""

name = "expat"
version = "2.7.0"
release = 1
summary = "流式 XML 解析库"
homepage = "https://libexpat.github.io"
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums expat
source = ["https://github.com/libexpat/libexpat/releases/download/R_2_7_0/expat-2.7.0.tar.gz"]
sha256 = ["362e89ca6b8a0d46fc5740a917eb2a8b4d6356edbe016eee09f49c0781215844"]

depends = []
makedepends = []
provides = ["libexpat.so.1"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
