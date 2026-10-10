"""base-config —— 澜岫系统基础配置（账户/网络/控制台/shell 环境）

Meta 性质：内容是精心准备的配置文件，不含远程源码。
许可证：MIT
"""

name = "base-config"
version = "0.1.0"
release = 1
summary = "系统基础配置：账户体系、profile、fstab、udhcpc 脚本、getty"
license = "MIT"

source = ["tests/demo/qydemo"]
sha256 = []

depends = ["busybox", "util-linux"]
provides = ["base-config"]


def fetch(ctx):
    pass  # 无远程源码


def build(ctx):
    pass


def package(ctx):
    d = str(ctx.destdir)
    src = str(ctx.srcdir)
    ctx.run("mkdir -p " + d + "/etc/qyinit.d " + d + "/usr/share/udhcpc " + d + "/var/spool/cron " + d + "/root")
    for f in ("passwd", "group", "profile", "motd", "hosts", "fstab", "resolv.conf"):
        ctx.run("cp " + src + "/etc/" + f + " " + d + "/etc/" + f)
    ctx.run("cp " + src + "/shadow.template " + d + "/etc/shadow")
    ctx.run("cp " + src + "/usr/share/udhcpc/default.script " + d + "/usr/share/udhcpc/")
    ctx.run("cp " + src + "/etc/qyinit.d/getty.unit " + d + "/etc/qyinit.d/")
    ctx.run("chmod 640 " + d + "/etc/shadow")
    ctx.run("chmod 755 " + d + "/usr/share/udhcpc/default.script")
