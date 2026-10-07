"""git —— 分布式版本控制系统


许可证：GPL-2.0-only
"""

name = "git"
version = "2.49.0"
release = 1
summary = "分布式版本控制系统"
homepage = ""
license = "GPL-2.0-only"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums git
source = ["https://www.kernel.org/pub/software/scm/git/git-2.49.0.tar.xz"]
sha256 = ["618190cf590b7e9f6c11f91f23b1d267cd98c3ab33b850416d8758f8b5a85628"]
checksum_pending = True

depends = ["curl", "openssl", "zlib", "expat", "pcre2"]
makedepends = ["curl", "openssl", "zlib", "expat", "pcre2"]
provides = ["vcs"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("""make prefix=/usr NO_PYTHON=1 NO_TCLTK=1 NO_DAEMON=1 \
    'CFLAGS=-O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' \
    'CURL_CONFIG={sysroot}/usr/bin/curl-config' \
    'LDFLAGS=-L{sysroot}/usr/lib -Wl,-rpath-link,{sysroot}/usr/lib'""".format(sysroot=ctx.sysroot))


def package(ctx):
    # install 阶段也要带同样参数，否则 make 会用默认 CFLAGS 重编 git-daemon
    flags = ("NO_PYTHON=1 NO_TCLTK=1 NO_DAEMON=1 "
             "'CFLAGS=-O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' "
             "'CURL_CONFIG={0}/usr/bin/curl-config' "
             "'LDFLAGS=-L{0}/usr/lib -Wl,-rpath-link,{0}/usr/lib'").format(ctx.sysroot)
    ctx.run("make prefix=/usr DESTDIR={} {} install".format(ctx.destdir, flags))
