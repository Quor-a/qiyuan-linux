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
    # openssl 的 ./config 只看 uname（会猜成 linux-x86_64）；
    # 交叉时必须显式 --target=linux-aarch64 且 CC 只给一次
    # （它内部还会把 CROSS_COMPILE 拼到 CC 前面，重复前缀 = 找不到命令）。
    if ctx.configure_args():
        ctx.run("./Configure linux-aarch64 --prefix=/usr "
                "--openssldir=/etc/ssl --libdir=lib shared zlib-dynamic "
                "CC=aarch64-qiyuan-linux-gnu-gcc")
    else:
        ctx.run("./config --prefix=/usr --openssldir=/etc/ssl "
                "--libdir=lib shared zlib-dynamic")
    ctx.run("make CROSS_COMPILE=")


def package(ctx):
    ctx.run("make DESTDIR={} CROSS_COMPILE= install_sw".format(ctx.destdir))
