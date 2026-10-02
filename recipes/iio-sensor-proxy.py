"""iio-sensor-proxy —— 陀螺仪/环境光传感器代理

许可证：GPL-3.0-or-later

屏幕自动旋转和自动亮度都靠它。没有它：
- 平板转屏不动（用户以为陀螺仪坏了）
- 自动亮度不工作

关键点：它是 D-Bus 服务，传感器数据不给应用直读，
因为直读等于任何应用都能持续获取设备朝向（隐私）。
"""
from __future__ import annotations

name = "iio-sensor-proxy"
version = "3.5"
release = 1
summary = "陀螺仪与环境光传感器代理"
homepage = "https://gitlab.freedesktop.org/hadess/iio-sensor-proxy"
license = "GPL-3.0-or-later"

source = []
sha256 = []

depends = ["glib", "dbus", "systemd"]
makedepends = ["meson", "ninja", "pkgconf", "glib", "dbus", "systemd"]
provides = ["orientation-sensor"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
