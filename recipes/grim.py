"""grim / slurp / wf-recorder —— Wayland 截图与录屏

许可证：MIT

Wayland 下截图不能靠 X11 的 xwd/import：
协议上客户端拿不到其他客户端的像素，必须由合成器提供。
没有这套工具，用户按截图键毫无反应——
而且不会报错，因为压根没人接收这个请求。
"""
from __future__ import annotations

name = "grim"
version = "1.4.1"
release = 1
summary = "Wayland 截图（grim/slurp/wf-recorder）"
homepage = "https://github.com/emersion/grim"
license = "MIT"

source = []
sha256 = []

depends = ["wayland", "libpng"]
makedepends = ["meson", "ninja", "pkgconf", "wayland", "libpng"]
provides = ["screenshot-tool", "screen-record-tool"]
requires_build_machine = False
network = False
compression = "gz"

# 上游源码地址尚未填回。与 checksum_pending 同一原则：
# 静默接受一个"没有来源"的配方，等于承认系统里有个来路不明的包。
# 填回 source/sha256 并补上 build()/package() 后再纳入构建
source_pending = True
