"""ca-certificates —— 系统可信 CA 证书集

https://curl.se/docs/caextract.html
许可证：MPL-2.0
"""

name = "ca-certificates"
version = "20250415"
release = 1
summary = "系统可信 CA 证书集"
homepage = "https://curl.se/docs/caextract.html"
license = "MPL-2.0"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums ca-certificates
source = ["https://deb.debian.org/debian/pool/main/c/ca-certificates/ca-certificates_20250419.tar.xz"]
sha256 = ["33b44ef78653ecd3f0f2f13e5bba6be466be2e7da72182f737912b81798ba5d2"]

depends = []
makedepends = []
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("mkdir -p {}/etc/ssl/certs".format(ctx.destdir))
    ctx.run("true  # 证书数据由独立的证书包提供")
