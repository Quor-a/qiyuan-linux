"""libical —— iCalendar 协议库

bluez（蓝牙 mesh/日历）等依赖。
许可证：MPL-2.0 OR LGPL-2.1
"""
from __future__ import annotations

name = "libical"
version = "3.0.20"
release = 1
summary = "iCalendar 协议解析库"
homepage = "https://github.com/libical/libical"
license = "MPL-2.0 OR LGPL-2.1-only"

source = ["https://github.com/libical/libical/releases/download/v3.0.20/libical-3.0.20.tar.gz"]
sha256 = ["e73de92f5a6ce84c1b00306446b290a2b08cdf0a80988eca0a2c9d5c3510b4c2"]
checksum_pending = False

depends = ["glib"]
makedepends = ["cmake", "glib", "libxml2", "icu"]
provides = ["ical"]

compression = "gz"


def build(ctx):
    ctx.out_of_tree()
    ctx.env("CMAKE_PREFIX_PATH", str(ctx.sysroot) + "/usr")
    ctx.env("CMAKE_FIND_ROOT_PATH", str(ctx.sysroot))
    # srcdir 即解包根（CMakeLists.txt 所在），out_of_tree 后 cwd=build
    ctx.run("cmake " + str(ctx.srcdir) + " -DCMAKE_INSTALL_PREFIX=/usr "
            "-DCMAKE_INSTALL_LIBDIR=lib "
            "-DSHARED_ONLY=true -DICAL_GLIB=true "
            "-DICAL_BUILD_DOCS=false "
            "-DGOBJECT_INTROSPECTION=false "
            "-DICAL_GLIB_VAPI=false "
            "-DUSE_BUILTIN_TZDATA=true")


def package(ctx):
    ctx.run("make -j2")
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
