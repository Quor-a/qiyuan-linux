"""libXdamage —— X 损坏区域扩展库


许可证：MIT
"""

name = "libXdamage"
version = "1.1.6"
release = 1
summary = "X 损坏区域扩展库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums libXdamage
source = ["https://www.x.org/archive/individual/lib/libXdamage-1.1.6.tar.xz"]
sha256 = ["52733c1f5262fca35f64e7d5060c6fcd81a880ba8e1e65c9621cf0727afb5d11"]

depends = ["libX11", "libXfixes", "damageproto"]
makedepends = ["libX11", "libXfixes", "damageproto"]
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
    ctx.run("./configure " + cv + " " + " ".join(ctx.configure_args()) + " --prefix=/usr")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
