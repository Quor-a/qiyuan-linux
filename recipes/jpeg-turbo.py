"""jpeg-turbo —— JPEG 编解码库（SIMD 加速）


许可证：IJG AND BSD-3-Clause AND Zlib
"""

name = "jpeg-turbo"
version = "3.1.0"
release = 1
summary = "JPEG 编解码库（SIMD 加速）"
homepage = ""
license = "IJG AND BSD-3-Clause AND Zlib"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums jpeg-turbo
source = ["https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/3.1.0.tar.gz"]
sha256 = ["35fec2e1ddfb05ecf6d93e50bc57c1e54bc81c16d611ddf6eff73fff266d8285"]

depends = []
makedepends = []
provides = ["libjpeg.so.62", "jpeg"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DENABLE_STATIC=OFF -DCMAKE_INSTALL_LIBDIR=lib .")
    ctx.run("ninja")


def package(ctx):
    ctx.run("DESTDIR={} ninja install".format(ctx.destdir))
    # libjpeg ABI 兼容链接：GTK/gdk-pixbuf 等按 libjpeg.so.62 (LIBJPEG_6.2 版本化符号) 链接，
    # 而 jpeg-turbo 默认只装 libturbojpeg.so；libjpeg.so.62.4.0 才是完整 jpeg ABI 库。
    ctx.run("cd {}/usr/lib && ln -sf libjpeg.so.62.4.0 libjpeg.so.62 && ln -sf libjpeg.so.62.4.0 libjpeg.so".format(ctx.destdir))
