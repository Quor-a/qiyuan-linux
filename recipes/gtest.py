"""gtest —— C++ 单元测试框架（构建期）

许可证：BSD-3-Clause

仅构建期需要，不进最终镜像。
protobuf、android-tools 的测试用。
"""
from __future__ import annotations

name = "gtest"
version = "1.15.2"
release = 1
summary = "C++ 单元测试框架（构建期）"
homepage = "https://google.github.io/googletest/"
license = "BSD-3-Clause"

source = ["https://ghproxy.net/https://github.com/google/googletest/archive/refs/tags/v1.16.0.tar.gz"]
sha256 = ["78c676fc63881529bf97bf9d45948d905a66833fbfa5318ea2cd7478cb98f399"]

depends = []
makedepends = ["cmake"]
provides = []
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("cmake -B build -DCMAKE_BUILD_TYPE=Release"
            " -DCMAKE_INSTALL_PREFIX=/usr")
    ctx.run("cmake --build build")


def package(ctx):
    ctx.run("DESTDIR={} cmake --install build".format(ctx.destdir))
