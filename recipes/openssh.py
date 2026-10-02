"""openssh —— SSH 客户端与服务端

https://www.openssh.com
许可证：BSD-2-Clause AND MIT
"""

name = "openssh"
version = "10.0p2"
release = 1
summary = "SSH 客户端与服务端"
homepage = "https://www.openssh.com"
license = "BSD-2-Clause AND MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums openssh
source = ["https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.0p2.tar.gz"]
sha256 = ["021a2e709a0edf4250b1256bd5a9e500411a90dddabea830ed59cef90eb9d85c"]

depends = ["openssl", "zlib"]
makedepends = ["openssl", "zlib"]
provides = ["ssh-server", "ssh"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    import os
    inc = os.path.join(str(ctx.sysroot), "usr/include")
    lib = os.path.join(str(ctx.sysroot), "usr/lib")
    ctx.run("./configure --prefix=/usr --sysconfdir=/etc/ssh --with-md5-passwords "
            "--with-privsep-path=/var/lib/sshd "
            "--with-openssl-opt=no "
            "CPPFLAGS=-I{inc} LDFLAGS='-L{lib} -Wl,-rpath,{lib}'".format(inc=inc, lib=lib))
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
