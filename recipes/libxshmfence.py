"""libxshmfence —— 共享内存同步原语（X 的 GLX 用）


许可证：MIT
"""

name = "libxshmfence"
version = "1.3.3"
release = 1
summary = "共享内存同步原语（X 的 GLX 用）"
homepage = ""
license = "MIT"

source = ["https://www.x.org/archive/individual/lib/libxshmfence-1.3.3.tar.xz"]
sha256 = ["d4a4df096aba96fea02c029ee3a44e11a47eb7f7213c1a729be83e85ec3fde10"]

depends = ["xorgproto"]
makedepends = ["xorgproto", "xorg-macros"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # 交叉时 malloc(0) 运行时测试无法执行——glibc 下结论固定，内联缓存变量钉死
    cv = "--enable-malloc0returnsnull=yes"
    # 交叉时 malloc(0) 等运行时测试无法执行——glibc 下结论固定，用缓存变量钉死
    ctx.env("ac_cv_func_malloc_0_nonnull", "yes")
    ctx.env("ac_cv_func_realloc_0_nonnull", "yes")
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
