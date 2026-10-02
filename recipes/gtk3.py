"""gtk3 —— GTK 3 图形界面工具包

许可证：LGPL-2.1-or-later
"""

name = "gtk3"
version = "3.24.43"
release = 1
summary = "GTK 3 图形界面工具包"
license = "LGPL-2.1-or-later"

source = ["https://download.gnome.org/sources/gtk+/3.24/gtk+-3.24.43.tar.xz"]
sha256 = ["7e04f0648515034b806b74ae5d774d87cffb1a2a96c468cb5be476d51bf2f3c7"]

depends = ["glib", "pango", "atk", "gdk-pixbuf", "cairo", "libX11", "libXext", "libXinerama", "libXi", "libXrandr", "libXcursor", "libXdamage", "libXcomposite", "wayland", "libepoxy", "harfbuzz", "fribidi", "iso-codes"]
makedepends = ["meson", "ninja", "gobject-introspection", "glib", "pango", "atk", "gdk-pixbuf", "cairo", "libX11", "libXext", "libXinerama", "libXi", "libXrandr", "libXcursor", "libXdamage", "libXcomposite", "wayland", "libepoxy", "harfbuzz", "fribidi", "iso-codes"]
provides = ["libgtk-3.so.0"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.run("export PATH={0}/usr/bin:$PATH; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && meson setup .. --prefix=/usr -Dbroadway_backend=false -Dgtk_doc=false -Dman=false -Dwayland_backend=true -Dx11_backend=false -Ddemos=false -Dintrospection=true '-Dc_args=-Wno-error=array-bounds -Dwerror=false'".format(ctx.sysroot))


def package(ctx):
    envp = "export PATH={0}/usr/bin:$PATH; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib;".format(ctx.sysroot)
    ctx.run(envp + " cd build && ninja")
    ctx.run(envp + " cd build && DESTDIR=" + str(ctx.destdir) + " ninja install")
