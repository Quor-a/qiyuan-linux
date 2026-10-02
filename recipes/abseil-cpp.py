"""abseil-cpp —— Google C++ 基础库（protobuf 依赖）

许可证：Apache-2.0
"""
from __future__ import annotations

name = "abseil-cpp"
version = "20250127"
release = 1
summary = "Google C++ 基础库"
homepage = "https://abseil.io/"
license = "Apache-2.0"

source = ["https://github.com/abseil/abseil-cpp/archive/refs/tags/20260107.0.tar.gz"]
sha256 = ["4c124408da902be896a2f368042729655709db5e3004ec99f57e3e14439bc1b2"]

depends = []
makedepends = ["cmake", "ninja"]
provides = []
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("cmake -B build -DCMAKE_BUILD_TYPE=Release"
            " -DCMAKE_INSTALL_PREFIX=/usr -DABSL_BUILD_TESTING=OFF")
    ctx.run("cmake --build build")


def package(ctx):
    ctx.run("DESTDIR={} cmake --install build".format(ctx.destdir))
