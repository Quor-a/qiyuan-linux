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
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    ctx.env("CFLAGS", (ctx.env("CFLAGS") or "") + " -Wno-error -Wno-format-nonliteral")
    # girepository/cmph 用 log/exp 等数学函数，glibc 下 libm 独立，必须显式 -lm
    ctx.env("LDFLAGS", (ctx.env("LDFLAGS") or "") + " -lm")
    # 交叉构建：introspection 必须关（g-ir-scanner 要在目标机跑 gobject，
    # 交叉时鸡生蛋）——纯库交叉通行做法；原生构建维持 enabled
    intro = "disabled" if cf else "enabled"
    pcpath = "" if cf else (
        "export PKG_CONFIG_PATH={0}/usr/lib/pkgconfig:{0}/usr/lib/x86_64-linux-gnu/pkgconfig:{0}/usr/share/pkgconfig; ".format(ctx.sysroot))
    giscan = "" if cf else (
        "export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; ".format(ctx.sysroot))
    ctx.run(f"rm -rf build && mkdir -p build")
    ctx.run("export PATH=$PATH:{0}/usr/bin; ".format(ctx.sysroot) + giscan + pcpath +
            "cd build && meson setup .. --prefix=/usr -Dman-pages=disabled -Ddocumentation=false "
            "-Dtests=false -Dintrospection=" + intro + " -Dglib_debug=disabled -Dselinux=disabled "
            "-Dsysprof=disabled -Dlibmount=enabled -Dxattr=false" + x)


def package(ctx):
    ctx.run("export PATH=$PATH:{0}/usr/bin; export PYTHONPATH={0}/usr/lib/x86_64-linux-gnu/gobject-introspection; export LD_LIBRARY_PATH={1}/../../../sysroot/lib:{0}/lib:{0}/usr/lib:{0}/usr/lib/x86_64-linux-gnu:{0}/lib/x86_64-linux-gnu; cd build && ninja".format(ctx.sysroot, ctx.srcdir))
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
