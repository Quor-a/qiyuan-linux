"""desktop-shell —— 状态栏、设置面板与工具调用入口

这是把系统能力暴露给桌面的那一层。没有它，
用户拿到的桌面只是"能画窗口"，改个时区还要开终端敲命令。

包含三块：
- 状态栏：网络、音量、电池、时间、输入法状态
- 设置面板：显示、声音、网络、蓝牙、账户、时间地区、电源
- 工具调用入口：把 qypkg/qynet/qylocale/qyapp 等命令
  包装成桌面能调用的动作（改设置需要提权，走 polkit）

**为什么工具调用必须走 polkit 而不是直接 root**
设置面板在用户会话里跑。直接给它 root，等于任何能画界面的程序
都能改系统配置。走 polkit 后：提权动作有单独的授权提示、
有审计记录、可以配置成"每次询问"。
"""
from __future__ import annotations

name = "desktop-shell"
version = "0.1.0"
release = 1
summary = "状态栏、设置面板与工具调用入口"
homepage = ""
license = "GPL-3.0-or-later"

source = []
sha256 = []

depends = ["gtk3", "polkit", "dbus", "networkmanager", "alsa-lib"]
makedepends = ["meson", "ninja", "gtk3", "polkit", "dbus", "networkmanager", "alsa-lib"]
provides = ["desktop-panel", "settings-panel"]
requires_build_machine = False
network = False
compression = "gz"


def build(ctx):
    ctx.log("桌面外壳由 qyos/desktop.py 生成配置与策略，无需编译")


def package(ctx):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from qyos import desktop as DS
    out = DS.install_layout(ctx.destdir)
    ctx.log(f"桌面外壳布局: {len(out)} 项")
