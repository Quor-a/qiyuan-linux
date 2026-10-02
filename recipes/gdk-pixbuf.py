"""gdk-pixbuf —— 图像加载库（GTK3 依赖）

许可证：LGPL-2.1-or-later
"""

name = "gdk-pixbuf"
version = "2.42.12"
release = 1
summary = "图像加载库（GTK3 依赖）"
license = "LGPL-2.1-or-later"

source = ["https://download.gnome.org/sources/gdk-pixbuf/2.42/gdk-pixbuf-2.42.12.tar.xz"]
sha256 = ["b9505b3445b9a7e48ced34760c3bcb73e966df3ac94c95a148cb669ab748e3c7"]

depends = ["glib", "libpng", "jpeg-turbo"]
makedepends = ["meson", "ninja", "glib", "gobject-introspection", "libpng", "jpeg-turbo"]

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.env("LDFLAGS", (ctx.env("LDFLAGS") or "") + " -lm")
    ctx.run("export PATH={0}/usr/bin:$PATH; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; meson setup build --prefix=/usr -Ddocs=false -Dintrospection=enabled -Dman=false -Dinstalled_tests=false -Dbuiltin_loaders=all -Drelocatable=false".format(ctx.sysroot))
    # builtin_loaders=none：PNG/GIF 等全部编译成动态 loader 模块并由 loaders.cache 注册。
    # 内置（builtin）模式下 loader 只在库初始化时静态注册，chroot/容器里常因
    # 资源路径与缓存缺失而识别不了 PNG（GTK 图标直接 assertion 崩）。


def package(ctx):
    ctx.run("export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; ninja -C build".format(ctx.sysroot))
    ctx.run("export PATH={0}/usr/bin:$PATH; DESTDIR={1} ninja -C build install".format(ctx.sysroot, ctx.destdir))
