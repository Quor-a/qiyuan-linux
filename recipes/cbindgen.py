"""cbindgen —— 由 Rust 代码生成 C 头文件（Firefox 依赖）

许可证：MPL-2.0
"""
from __future__ import annotations

name = "cbindgen"
version = "0.29.0"
release = 1
summary = "从 Rust 生成 C 头文件"
homepage = "https://github.com/mozilla/cbindgen"
license = "MPL-2.0"

source = ["https://github.com/mozilla/cbindgen/archive/refs/tags/v0.29.0.tar.gz"]
sha256 = ["6697f449d4a15d814d991249a611af961c97e36d9344c7ced6df35c5c25b40cc"]


depends = ["rust"]
makedepends = ["cargo", "rust"]
provides = []
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("cargo build --release")


def package(ctx):
    import os
    b = os.path.join(ctx.destdir, "usr", "bin")
    os.makedirs(b, exist_ok=True)
    ctx.run("install -m 755 target/release/cbindgen {}/cbindgen".format(b))
