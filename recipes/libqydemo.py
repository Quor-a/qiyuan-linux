"""libqydemo —— 演示库配方。

展示配方的完整字段与 build()/package() 两段式写法。
真实发行版里这类配方会指向上游发布包 + sha256；这里用本地源码目录，
方便在无网环境跑通端到端验证。
"""

name = "libqydemo"
version = "0.2.0"
release = 1
summary = "澜岫构建系统演示共享库"
description = "提供版本查询与加法运算的最小共享库，用于验证构建链路。"
homepage = "https://example.invalid/lanxiu"
license = "MIT"

source = ["tests/demo/libqydemo"]
sha256 = []

# 注意：自举完成前，本包链接的是宿主的 libc。
# 等 glibc 成为仓库里的正式包之后，这里必须补上 depends = ["glibc"]，
# 否则"glibc 出 CVE 谁要重编"这类查询会漏掉它。
depends = []
makedepends = ["glibc"]
provides = ["libqydemo.so.1"]

network = False
compression = "gz"


def build(ctx):
    ctx.run("make PREFIX=/usr LIBDIR=/usr/lib")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    # 清理不该进包的构建产物
    ctx.rm("usr/lib/*.a")
