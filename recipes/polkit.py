"""polkit —— 权限授权框架（桌面提权弹窗）

许可证：LGPL-2.0-or-later
"""

name = "polkit"
version = "126"
release = 1
summary = "权限授权框架（桌面提权弹窗）"
license = "LGPL-2.0-or-later"

source = ["https://github.com/polkit-org/polkit/archive/refs/tags/126.tar.gz"]
sha256 = ["2814a7281989f6baa9e57bd33bbc5e148827e2721ccef22aaf28ab2b376068e8"]

depends = ["glib", "dbus", "pam"]
makedepends = ["meson", "ninja", "gobject-introspection", "glib", "dbus", "pam"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = (f" --cross-file={cf} --native-file={cf.replace('qy-cross.ini', 'qy-native.ini')}" if cf else "")
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("rm -rf build && mkdir -p build")
    import os
    tb = os.path.join(str(ctx.builddir), "toolbin")
    os.makedirs(tb, exist_ok=True)
    mf = os.path.join(str(ctx.sysroot), "usr/bin/msgfmt")
    link = os.path.join(tb, "msgfmt")
    if not os.path.exists(link):
        os.symlink(mf, link)
    ctx.run("export PATH={tb}:$PATH; cd build && meson setup .. --prefix=/usr -Dsession_tracking=ConsoleKit -Dlibs-only=true -Dintrospection=false -Dexamples=false".format(tb=tb))


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={} ninja install".format(ctx.destdir))
