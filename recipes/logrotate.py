"""logrotate —— 系统日志轮转工具（系统必备）

https://github.com/logrotate/logrotate
许可证：GPL-2.0+
"""

name = "logrotate"
version = "3.22.0"
release = 1
summary = "日志文件轮转、压缩与删除"
homepage = "https://github.com/logrotate/logrotate"
license = "GPL-2.0+"

source = ["https://github.com/logrotate/logrotate/releases/download/3.22.0/logrotate-3.22.0.tar.xz"]
sha256 = ["42b4080ee99c9fb6a7d12d8e787637d057a635194e25971997eebbe8d5e57618"]

depends = ["popt"]


def fetch(ctx):
    ctx.default_fetch()


def build(ctx):
    # popt 装在 sysroot：configure 的链接 run-test 会撞宿主 libpopt 段错误，
    # 用缓存变量跳过；头文件/库路径显式传（Makefile 会覆盖注入的 CFLAGS）。
    sr = ctx.sysroot
    ctx.run("./configure --prefix=/usr --sysconfdir=/etc "
            "--with-acl=no --with-selinux=no --without-systemd "
            "ac_cv_func_poptParseArgvString=yes "
            "ac_cv_lib_popt_poptParseArgvString=yes "
            "ac_cv_header_popt_h=yes "
            "CPPFLAGS=-I{}/usr/include LDFLAGS=-L{}/usr/lib".format(sr, sr))
    ctx.run("make -j2")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    ctx.run("mkdir -p {}/etc/logrotate.d".format(ctx.destdir))
