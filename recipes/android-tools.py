"""android-tools —— adb / fastboot

许可证：Apache-2.0 AND BSD-3-Clause

ADB 是与安卓设备通信的唯一通道：调试、传文件、刷机、无线调试都靠它。
做安卓适配的发行版没有 adb，等于没法验证自己做的东西。

无线调试（adb tcpip / adb pair）在 Android 11+ 是标准功能，
不需要数据线——配对码 + 端口，比 USB 更方便也更安全
（不暴露 USB 调试给所有连过的电脑）。
"""
from __future__ import annotations

name = "android-tools"
version = "35.0.2"
release = 1
summary = "adb / fastboot（安卓设备调试与刷机）"
homepage = "https://github.com/nmeum/android-tools"
license = "Apache-2.0 AND BSD-3-Clause"

source = ["https://github.com/nmeum/android-tools/archive/refs/tags/35.0.2.tar.gz"]
sha256 = ["048bd42b75166fa4b66989b25ba1abb2b773aa7b7d012d52d84010b127db8801"]


depends = ["libusb", "brotli", "protobuf"]
makedepends = ["cmake", "pkgconf", "gtest", "libusb", "brotli", "protobuf"]
provides = ["adb", "fastboot"]
requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.run("cmake -B build -DCMAKE_BUILD_TYPE=Release"
            " -DCMAKE_INSTALL_PREFIX=/usr")
    ctx.run("cmake --build build")


def package(ctx):
    ctx.run("DESTDIR={} cmake --install build".format(ctx.destdir))
