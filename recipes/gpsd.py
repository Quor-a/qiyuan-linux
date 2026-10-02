"""gpsd —— GPS 定位服务

许可证：BSD-2-Clause

GPS 模块多走串口或 USB，gpsd 统一成上层可用的接口。
没有它每个应用都要自己解析 NMEA，且会互相抢串口。
"""
from __future__ import annotations

name = "gpsd"
version = "3.25"
release = 1
summary = "GPS 定位服务"
homepage = "https://gpsd.io/"
license = "BSD-2-Clause"

source = []
sha256 = []

depends = ["libusb", "ncurses"]
makedepends = ["python", "scons", "libusb", "ncurses"]
provides = ["gps"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
