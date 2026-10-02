"""atk —— 无障碍工具包（GTK3 依赖）

许可证：LGPL-2.1-or-later
"""

name = "atk"
version = "2.38.0"
release = 1
summary = "无障碍工具包（GTK3 依赖）"
license = "LGPL-2.1-or-later"

source = ["https://download.gnome.org/sources/atk/2.38/atk-2.38.0.tar.xz"]
sha256 = ["ac4de2a4ef4bd5665052952fe169657e65e895c5057dffb3c2a810f6191a0c36"]

depends = ["glib"]
makedepends = ["meson", "ninja", "glib", "gobject-introspection"]

requires_build_machine = True
network = False
compression = "xz"


def build(ctx):
    ctx.env("LDFLAGS", (ctx.env("LDFLAGS") or "") + " -lm")
    ctx.run("export PATH={0}/usr/bin:$PATH; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; meson setup build --prefix=/usr -Ddocs=false -Dintrospection=true".format(ctx.sysroot))


def package(ctx):
    ctx.run("export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; ninja -C build".format(ctx.sysroot))
    ctx.run("export PATH={0}/usr/bin:$PATH; DESTDIR={1} ninja -C build install".format(ctx.sysroot, ctx.destdir))
