"""curl —— 命令行数据传输工具与 libcurl

https://curl.se
许可证：curl
"""

name = "curl"
version = "8.13.0"
release = 1
summary = "命令行数据传输工具与 libcurl"
homepage = "https://curl.se"
license = "curl"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums curl
source = ["https://curl.se/download/curl-8.13.0.tar.xz"]
sha256 = ["4a093979a3c2d02de2fbc00549a32771007f2e78032c6faa5ecd2f7a9e152025"]

depends = ["openssl", "zlib", "zstd"]
makedepends = ["openssl", "zlib", "zstd"]
provides = ["libcurl.so.4"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static --with-openssl --with-zlib --with-zstd --enable-threaded-resolver --without-libpsl")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
