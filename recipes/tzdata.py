"""tzdata —— 时区数据库

https://www.iana.org/time-zones
许可证：PublicDomain
"""

name = "tzdata"
version = "2025b"
release = 1
summary = "时区数据库"
homepage = "https://www.iana.org/time-zones"
license = "PublicDomain"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums tzdata
source = ["https://data.iana.org/time-zones/releases/tzdata2025b.tar.gz"]
sha256 = ["11810413345fc7805017e27ea9fa4885fd74cd61b2911711ad038f5d28d71474"]

depends = []
makedepends = []
provides = []

# 需要真实构建机：要下载源码并编译，时长与磁盘门槛不满足时不该被静默带进构建
requires_build_machine = True

network = False
compression = "gz"
strip_components = 0


def build(ctx):
    ctx.run("true")


def package(ctx):
    import os
    d = str(ctx.destdir).rstrip("/")
    zoneinfo = os.path.join(d, "usr/share/zoneinfo")
    os.makedirs(zoneinfo, exist_ok=True)
    # 用 zic 编译时区主文件 (fat 完整集)
    ctx.run("/usr/sbin/zic -d {z} africa antarctica asia australasia europe northamerica "
            "southamerica etcetera backward factory".format(z=zoneinfo))
    # posix/right 变体 + leapseconds 若存在
    if os.path.exists("leapseconds"):
        ctx.run("/usr/sbin/zic -L leapseconds -d {z}/right africa antarctica asia australasia "
                "europe northamerica southamerica etcetera backward factory".format(z=zoneinfo))
    ctx.run("/usr/sbin/zic -d {z} -p America/New_York".format(z=zoneinfo))
