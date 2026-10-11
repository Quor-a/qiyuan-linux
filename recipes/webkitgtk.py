"""WebKitGTK —— 轻量浏览器内核（Safari 同源引擎的 Linux GTK 移植）

许可证：LGPL-2.1-or-later / BSD-2
设计依据：发行版浏览器决策（用户 2026-10-08 "轻量浏览器"）——
  Firefox 构建要 4-8 小时/几十 GB，进不了发行版流水线；
  WebKitGTK 是唯一可维护的轻量选择，上承 GNOME Web，
  下承自定义极简壳（tests/demo/mini-browser.c）。
构建策略： minimal 选项集 + 关闭不需要的编解码器（对应零专利费路线：
  不内置 H.264/H.265/AAC，视频走 VP9/AV1 需要 gst 插件、先关闭以保证可构建）。
"""

name = "webkitgtk"
version = "2.46.6"
release = 1
summary = "轻量浏览器渲染内核（WebKit 的 GTK 移植）"
license = "LGPL-2.1-or-later"

source = ["https://webkitgtk.org/releases/webkitgtk-2.46.6.tar.xz"]
sha256 = ["f2b31de693220ba9bab76ce6ddfe5b0bfab2515cb2b0a70f3c54d4050766c32b"]
checksum_pending = False

depends = ["glib", "gtk3", "libsoup", "harfbuzz", "cairo", "pango", "atk",
           "gdk-pixbuf", "libxml2", "libxslt", "sqlite", "icu", "wayland",
           "mesa", "libdrm", "libwebp", "libepoxy"]
makedepends = ["cmake", "ninja", "glib", "gtk3", "libsoup", "harfbuzz",
               "cairo", "pango", "atk", "gdk-pixbuf", "libxml2", "libxslt",
               "sqlite", "icu", "wayland", "mesa", "libdrm", "libwebp",
               "libepoxy", "python"]
provides = ["libwebkit2gtk-4.1.so.0"]

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    sysroot = ctx.sysroot
    env = ("export PATH=$PATH:{0}/usr/bin; "
           "export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; "
           "export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; "
           ).format(sysroot)
    ctx.out_of_tree()
    ctx.run(env + "cmake " + str(ctx.srcdir) + " "
                  "-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr "
                  "-DPORT=GTK -DENABLE_WEBKIT=ON -DENABLE_MINIBROWSER=ON "
                  "-DENABLE_WEBDRIVER=OFF -DENABLE_BUBBLEWRAP_SANDBOX=OFF "
                  "-DENABLE_GEOLOCATION=OFF -DENABLE_MEDIA_STREAM=OFF "
                  "-DENABLE_VIDEO=OFF -DENABLE_WEB_AUDIO=OFF "
                  "-DUSE_GSTREAMER_GL=OFF -DUSE_SOUP2=OFF "
                  "-DUSE_WOFF2=OFF -DENABLE_INTROSPECTION=OFF "
                  "-DUSE_GTK4=OFF -DUSE_JPEGXL=OFF -DUSE_AVIF=OFF "
                  "-DENABLE_GAMEPAD=OFF "
                  "-DUSE_SYSTEMD=OFF -DENABLE_DOCUMENTATION=OFF".format())


def package(ctx):
    sysroot = ctx.sysroot
    env = ("export PATH=$PATH:{0}/usr/bin; "
           "export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; "
           ).format(sysroot)
    ctx.run(env + "ninja")
    ctx.run(env + "DESTDIR=" + str(ctx.destdir) + " ninja install")
