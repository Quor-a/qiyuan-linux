"""Dillo —— 极轻量浏览器（自研渲染引擎，C/C++ + FLTK）

许可证：GPL-3.0
设计依据：用户 2026-10-08 "轻量浏览器"决策。
WebKitGTK 需要 Ruby 等重型工具链（本发行版自举环境无），改用 Dillo：
  - 自带实时渲染引擎（不依赖 WebKit/Blink/Gecko）
  - 二进制 ~1MB，内存个位数 MB，2-3 分钟编译完
  - 支持 HTTPS（内嵌 Mbed TLS）、WebP/SVG 图片、CSS 子集
WebKitGTK 配方保留（recipes/webkitgtk.py），作为仓库可选包，
待补齐 ruby/bison 自举工具链后再启用。
"""

name = "dillo"
version = "3.2.0"
release = 1
summary = "极轻量浏览器（自研引擎，约 1MB）"
license = "GPL-3.0"

source = ["https://github.com/dillo-browser/dillo/archive/refs/tags/v3.2.0.tar.gz"]
sha256 = ["4282e4bc0de229d23cd3e36dda81bba9267709c76d59d592c429d4532cf1d451"]
checksum_pending = False

depends = ["zlib", "libpng", "openssl", "glib"]
makedepends = ["zlib", "libpng", "openssl", "glib"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # 上游 tarball 不带 configure，需 autogen（宿主有 autoconf/automake）
    ctx.run("./autogen.sh")
    # 宿主工具链有 bison/flex/gperf/perl；FLTK 由 dillo 内嵌实现（3.2 起）
    ctx.env("FLTK_CONFIG", "{0}/usr/bin/fltk-config".format(ctx.sysroot))
    ctx.run("./configure --prefix=/usr --sysconfdir=/etc "
            "--enable-tls --disable-xembed "
            "ac_cv_path_FLTK_CONFIG={}/usr/bin/fltk-config".format(ctx.sysroot))
    ctx.run("make -j{}".format(ctx.jobs))


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
