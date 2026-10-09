"""libwebp —— WebP 图像格式库


许可证：BSD-3-Clause
"""

name = "libwebp"
version = "1.5.0"
release = 1
summary = "WebP 图像格式库"
homepage = ""
license = "BSD-3-Clause"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libwebp
source = ["https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.5.0.tar.gz"]
sha256 = ["7d6fab70cf844bf6769077bd5d7a74893f8ffd4dfb42861745750c63c2a5c92c"]

depends = ["libpng", "jpeg-turbo", "libtiff", "giflib"]
makedepends = ["libpng", "jpeg-turbo", "libtiff", "giflib"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --enable-libwebpmux --enable-libwebpdemux --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
