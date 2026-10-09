"""pango —— 文本布局与渲染库

许可证：LGPL-2.1-or-later
"""

name = "pango"
version = "1.56.3"
release = 1
summary = "文本布局与渲染库"
license = "LGPL-2.1-or-later"

source = ["https://download.gnome.org/sources/pango/1.56/pango-1.56.3.tar.xz"]
sha256 = ["2606252bc25cd8d24e1b7f7e92c3a272b37acd6734347b73b47a482834ba2491"]

depends = ["glib", "cairo", "harfbuzz", "fribidi", "freetype", "fontconfig"]
makedepends = ["meson", "ninja", "glib", "cairo", "harfbuzz", "fribidi", "freetype", "fontconfig"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("sed -i 's/-Werror=redundant-decls/-Wno-redundant-decls/' meson.build")
    ctx.env("CFLAGS", (ctx.env("CFLAGS") or "") + " -Wno-error -Wno-redundant-decls")
    ctx.run("export PATH={0}/usr/bin:$PATH; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && meson setup .. --prefix=/usr -Ddocumentation=false -Dintrospection=disabled -Dxft=disabled -Dcpp_args=-Wno-redundant-decls,-Wno-format-nonliteral,-Wno-undef".format(ctx.sysroot))


def package(ctx):
    ctx.run("export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; cd build && ninja".format(ctx.sysroot))
    ctx.run("export PATH={0}/usr/bin:$PATH; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && DESTDIR=".format(ctx.sysroot)+str(ctx.destdir)+" ninja install")
