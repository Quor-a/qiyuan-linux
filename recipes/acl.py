"""acl —— 访问控制列表库


许可证：LGPL-2.1-or-later AND GPL-2.0-or-later
"""

name = "acl"
version = "2.3.2"
release = 1
summary = "访问控制列表库"
homepage = ""
license = "LGPL-2.1-or-later AND GPL-2.0-or-later"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums acl
source = ["https://download.savannah.nongnu.org/releases/acl/acl-2.3.2.tar.xz"]
sha256 = ["97203a72cae99ab89a067fe2210c1cbf052bc492b479eca7d226d9830883b0bd"]
checksum_pending = True

depends = []
makedepends = []
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    import os
    inc = os.path.join(str(ctx.sysroot), "usr/include")
    lib = os.path.join(str(ctx.sysroot), "usr/lib")
    ctx.run("./configure" + " " .join(ctx.configure_args()) + " --prefix=/usr --disable-static CPPFLAGS=-I{inc} LDFLAGS=-L{lib}".format(inc=inc, lib=lib))
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
