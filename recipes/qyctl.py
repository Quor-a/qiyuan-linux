"""qyctl —— 澜岫服务管理 CLI（无 dbus/polkit 依赖）。"""

name = "qyctl"
version = "0.1.0"
release = 1
summary = "澜岫 Linux 服务管理 CLI"
description = "list/status/start/stop/restart/enable/disable；与 qyinit 通过 /run/qyinit/units/<name>.pid 契约协作。"
license = "MIT"

source = ["recipes/qyctl.c"]
sha256 = []

depends = ["glibc"]
makedepends = []

network = False
compression = "gz"


def build(ctx):
    ctx.run(
        "gcc -Os -Wall -o qyctl recipes/qyctl.c"
    )


def package(ctx):
    ctx.install_file("qyctl", "usr/bin/qyctl")
    ctx.run("chmod 0755 {}/usr/bin/qyctl".format(ctx.destdir))
