"""openssl —— TLS/SSL 与通用密码学库

https://www.openssl.org
许可证：Apache-2.0
"""

name = "openssl"
version = "3.5.0"
release = 1
summary = "TLS/SSL 与通用密码学库"
homepage = "https://www.openssl.org"
license = "Apache-2.0"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums openssl
source = ["https://github.com/openssl/openssl/releases/download/openssl-3.5.0/openssl-3.5.0.tar.gz"]
sha256 = ["344d0a79f1a9b08029b0744e2cc401a43f9c90acd1044d09a530b4885a8e9fc0"]

depends = ["zlib"]
makedepends = ["zlib"]
provides = ["libssl.so.3", "libcrypto.so.3"]

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install_sw".format(ctx.destdir))
