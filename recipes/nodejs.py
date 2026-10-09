"""nodejs —— JavaScript 运行时（构建 Firefox 等需要）

许可证：MIT

构建期依赖：Firefox 的前端构建链要它。
不进最终镜像（除非用户装）。
"""
from __future__ import annotations

name = "nodejs"
version = "22.14.0"
release = 1
summary = "JavaScript 运行时"
homepage = "https://nodejs.org/"
license = "MIT"

source = ["https://nodejs.org/dist/v22.14.0/node-v22.14.0.tar.xz"]
sha256 = ["c609946bf793b55c7954c26582760808d54c16185d79cb2fb88065e52de21914"]

depends = ["openssl", "zlib", "icu"]
makedepends = ["python", "ninja", "openssl", "zlib", "icu"]
provides = ["node"]
requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --without-npm")
    ctx.run("make -j1")     # 并行构建 node 容易 OOM，串行更稳


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
