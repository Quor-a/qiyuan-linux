"""qyinit —— 澜岫 Linux 的 1 号进程与服务管理器。

一个真正的 init 该做的事：挂载早期文件系统、创建设备节点、按依赖顺序启动
服务、回收孤儿进程、处理关机信号、按策略重启崩溃的服务。

刻意保持小而可审计——init 是整个系统里最不该出 bug 的程序。
"""

name = "qyinit"
version = "0.1.0"
release = 1
summary = "澜岫 Linux 初始化与服务管理（PID 1）"
description = "挂载早期文件系统、按依赖顺序启动服务、回收孤儿进程、处理关机流程。"
license = "MIT"

source = ["tests/demo/qyinit"]
sha256 = []

# 注意：自举完成前，本包链接的是宿主的 libc。
# 等 glibc 成为仓库里的正式包之后，这里必须补上 depends = ["glibc"]，
# 否则"glibc 出 CVE 谁要重编"这类查询会漏掉它。
depends = []
makedepends = ["glibc"]
provides = ["init"]

network = False
compression = "gz"


def build(ctx):
    # init 在 switch_root 时 /usr 尚未就绪，动态链接器找不到 libc 会直接
    # panic（"Attempted to kill init"）。README 硬规矩：早期 init 强制静态。
    ctx.run("make CC=gcc PREFIX=/usr LDFLAGS=-static")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    # 安装默认服务单元目录与一个最小单元集，装机后可直接启动
    ctx.install_file("units/hostname.unit", "etc/qyinit.d/hostname.unit")
    ctx.install_file("units/sysctl.unit", "etc/qyinit.d/sysctl.unit")
    # /sbin/init 是内核默认找的位置，必须有
    ctx.run("mkdir -p {}/sbin {}/usr/sbin".format(ctx.destdir, ctx.destdir))
    ctx.run("ln -sf /usr/bin/qyinit {}/sbin/init".format(ctx.destdir))
    ctx.run("ln -sf /usr/bin/qyinit {}/usr/sbin/init".format(ctx.destdir))
