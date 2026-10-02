"""protobuf —— 结构化数据序列化（ADB 依赖）

许可证：BSD-3-Clause

ADB 协议用它编码消息。不是可选依赖。
"""
from __future__ import annotations

name = "protobuf"
version = "31.1"
release = 1
summary = "结构化数据序列化"
homepage = "https://protobuf.dev/"
license = "BSD-3-Clause"

source = ["https://ghproxy.net/https://github.com/protocolbuffers/protobuf/releases/download/v31.1/protobuf-31.1.tar.gz"]
sha256 = ["008a11cc56f9b96679b4c285fd05f46d317d685be3ab524b2a310be0fbad987e"]

depends = ["zlib"]
makedepends = ["cmake", "ninja", "abseil-cpp", "zlib"]
provides = ["protobuf-lite"]
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("cmake -B build -DCMAKE_BUILD_TYPE=Release"
            " -DCMAKE_INSTALL_PREFIX=/usr -Dprotobuf_BUILD_TESTS=OFF")
    ctx.run("cmake --build build")


def package(ctx):
    ctx.run("DESTDIR={} cmake --install build".format(ctx.destdir))
