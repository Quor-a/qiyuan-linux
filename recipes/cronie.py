"""cronie —— 定时任务守护进程（cron 的现代分支，系统必备）

https://github.com/cronie-crond/cronie
许可证：MIT
"""

name = "cronie"
version = "1.7.2"
release = 1
summary = "cron 定时任务守护进程"
homepage = "https://github.com/cronie-crond/cronie"
license = "MIT"

source = ["https://github.com/cronie-crond/cronie/releases/download/cronie-1.7.2/cronie-1.7.2.tar.gz"]
sha256 = ["f1da374a15ba7605cf378347f96bc8b678d3d7c0765269c8242cfe5b0789c571"]

depends = ["pam"]


def fetch(ctx):
    ctx.default_fetch()


def build(ctx):
    ctx.run("./configure" + " " .join(ctx.configure_args()) + " --prefix=/usr --sysconfdir=/etc --with-inotify=no "
            "--without-selinux --without-acl --disable-anacron")
    ctx.run("make -j2")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    # cronie 运行必需：spool 目录（存在才不退出）
    ctx.run("mkdir -p {}/var/spool/cron {}/usr/var/run {}/usr/var/spool/cron".format(ctx.destdir, ctx.destdir, ctx.destdir))
    ctx.run("mkdir -p {}/etc/qyinit.d".format(ctx.destdir))
    ctx.run("cp etc/qyinit.d/crond.unit {{}}/etc/qyinit.d/ || true".format(ctx.destdir))
