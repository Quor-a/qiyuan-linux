"""firefox —— 网页浏览器

许可证：MPL-2.0

内置浏览器不是"装个应用"这么简单：它是系统里最大的
第三方代码信任域。所以单独建配方并明确：
- 沙箱（flatpak 形态或自带 content sandbox）
- 更新走系统包管理还是自更新（自更新会绕过发行版审计）
"""
from __future__ import annotations

name = "firefox"
version = "142.0"
release = 1
summary = "网页浏览器"
homepage = "https://www.mozilla.org/firefox/"
license = "MPL-2.0"

source = ["https://ftp.mozilla.org/pub/firefox/releases/142.0/source/firefox-142.0.source.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["gtk3", "dbus", "ffmpeg", "libwebp"]
makedepends = ["python", "nodejs", "rust", "cbindgen", "gtk3", "dbus", "ffmpeg", "libwebp"]
provides = ["web-browser", "x-www-browser"]
requires_build_machine = True
network = False
compression = "xz"

# 自更新会绕过发行版审计：浏览器自己下载代码替换自己，
# 我们既不知道装了什么也说不清出问题时跑的是什么版本
NO_SELF_UPDATE = True


def build(ctx):
    ctx.run("./mach configure --prefix=/usr")
    ctx.run("./mach build")


def package(ctx):
    ctx.run("./mach install DESTDIR={}".format(ctx.destdir))
