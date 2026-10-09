"""rust —— Rust 编译器（Firefox 依赖）

许可证：MIT OR Apache-2.0

Firefox 的绝大部分内存安全代码是 Rust 写的。
没有它编不出浏览器。
"""
from __future__ import annotations

name = "rust"
version = "1.85.0"
release = 1
summary = "Rust 编译器与工具链"
homepage = "https://www.rust-lang.org/"
license = "MIT OR Apache-2.0"

source = ["https://static.rust-lang.org/dist/rustc-1.85.0-src.tar.xz"]
sha256 = ["d542c397217b5ba5bac7eb274f5ca62d031f61842c3ba4cc5328c709c38ea1e7"]

depends = ["gcc", "curl"]
makedepends = ["python", "cmake", "ninja", "gcc", "curl"]
provides = ["rustc", "cargo"]
requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.run("./configure" + " " .join(ctx.configure_args()) + " --prefix=/usr --release-channel=stable"
            " --disable-docs")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
