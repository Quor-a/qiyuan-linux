"""systemd —— 基础库与服务管理兼容层

许可证：LGPL-2.1-or-later

说明：启元的 1 号进程是 qyinit，不是 systemd。
但相当多上游软件（iio-sensor-proxy、power-profiles-daemon 等）
依赖 systemd 的库和 udev/sysusers 工具链。

所以这里只取**库与工具**，不取 init。
用 systemd 的 init 会与 qyinit 冲突，那是真正的架构倒退。
"""
from __future__ import annotations

name = "systemd"
version = "257.4"
release = 1
summary = "systemd 库与工具（不含 init）"
homepage = "https://systemd.io/"
license = "LGPL-2.1-or-later"

source = []
sha256 = []

depends = ["glibc", "libcap", "util-linux"]
makedepends = ["meson", "ninja", "pkgconf", "gperf", "glibc", "libcap", "util-linux"]
provides = ["libsystemd.so.0", "udev"]
# 关键：只装库与工具，不装 init。
# 装了 init 会顶掉 qyinit
EXCLUDE_INIT = True
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
