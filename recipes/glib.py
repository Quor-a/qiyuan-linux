"""glib —— 通用工具与对象库（GTK 与大量应用的基础）

许可证：LGPL-2.1-or-later
"""

name = "glib"
version = "2.84.0"
release = 1
summary = "通用工具与对象库（GTK 与大量应用的基础）"
license = "LGPL-2.1-or-later"

source = ["https://download.gnome.org/sources/glib/2.84/glib-2.84.0.tar.xz"]
sha256 = ["f8823600cb85425e2815cfad82ea20fdaa538482ab74e7293d58b3f64a5aff6a"]

depends = ["libffi", "pcre2", "zlib", "libxml2", "util-linux"]
makedepends = ["meson", "ninja", "python", "libffi", "pcre2", "zlib", "libxml2", "util-linux"]
provides = ["libglib-2.0.so.0"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.env("CFLAGS", (ctx.env("CFLAGS") or "") + " -Wno-error -Wno-format-nonliteral")
    # girepository/cmph 用 log/exp 等数学函数，glibc 下 libm 独立，必须显式 -lm
    ctx.env("LDFLAGS", (ctx.env("LDFLAGS") or "") + " -lm")
    # introspection 需要: sysroot 工具链 PATH + giscanner PYTHONPATH (cpython-312
    # tag 的 _giscanner 必须用 python3.12 跑, 故 g-ir-scanner shebang 钉 3.12)
    # + gi 的 pkgconfig (g_ir_scanner 变量指 sysroot) + -lm (girepository/cmph)
    ctx.run("export PATH={0}/usr/bin:$PATH; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; cd build && meson setup .. --prefix=/usr -Dman-pages=disabled -Ddocumentation=false -Dtests=false -Dintrospection=enabled -Dglib_debug=disabled -Dselinux=disabled -Dlibmount=enabled -Dxattr=false".format(ctx.sysroot))


def package(ctx):
    ctx.run("export PATH={0}/usr/bin:$PATH; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; export LD_LIBRARY_PATH={0}/usr/lib/x86_64-linux-gnu:{0}/usr/lib:{0}/lib; cd build && ninja".format(ctx.sysroot))
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
