"""busybox —— 静态多合一工具箱（udhcpc/救援 shell 依赖）

许可证：GPL-2.0-or-later
"""

name = "busybox"
version = "1.36.1"
release = 1
summary = "静态多合一 Unix 工具箱"
license = "GPL-2.0-or-later"

source = ["https://busybox.net/downloads/busybox-1.36.1.tar.bz2"]
sha256 = ["b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314"]

depends = []
makedepends = []
provides = ["udhcpc"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    # 全默认配置 + 静态链接（救援/网络自启都要求不依赖 libc 安装状态）
    ctx.run("make defconfig")

    # tc 依赖 linux-atm 头（宿主没有），本系统用不上它
    ctx.run("sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config")
    ctx.run("make -j2 CONFIG_STATIC=y")


def package(ctx):
    # coreutils/util-linux 已提供全部常规工具；busybox 在本系统只承担
    # 两个角色：udhcpc（网络自启）与 /bin/sh 救援 shell。
    # 手动安装，避免 make install 覆盖 coreutils 的同名工具。
    ctx.run("mkdir -p {}/usr/bin {}/usr/sbin {}/bin".format(ctx.destdir, ctx.destdir, ctx.destdir))
    ctx.run("cp busybox {}/usr/bin/busybox".format(ctx.destdir))
    ctx.run("chmod 755 {}/usr/bin/busybox".format(ctx.destdir))
    ctx.run("ln -sf busybox {}/usr/bin/udhcpc".format(ctx.destdir))
    ctx.run("ln -sf busybox {}/usr/bin/hostname".format(ctx.destdir))
    ctx.run("ln -sf /usr/bin/busybox {}/bin/sh".format(ctx.destdir))
