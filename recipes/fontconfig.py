"""fontconfig —— 字体配置与匹配库


许可证：MIT
"""

name = "fontconfig"
version = "2.16.0"
release = 1
summary = "字体配置与匹配库"
homepage = ""
license = "MIT"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums fontconfig
source = ["https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.16.0.tar.xz"]
sha256 = ["6a33dc555cc9ba8b10caf7695878ef134eeb36d0af366041f639b1da9b6ed220"]

depends = ["freetype", "expat", "libxml2"]
makedepends = ["gperf", "freetype", "expat", "libxml2"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    # pango 的 PangoFc introspection include 需要 fontconfig-2.0.gir；
    # upstream fontconfig 不生成 gir，手写最小版满足 g-ir-scanner 的 include 解析。
    import shutil
    if shutil.which("g-ir-scanner") is None:
        return
    gir = ctx.destdir / "usr" / "share" / "gir-1.0"
    gir.mkdir(parents=True, exist_ok=True)
    (gir / "fontconfig-2.0.gir").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<repository version="1.2"\n'
        '            xmlns="http://www.gtk.org/introspection/core/1.0"\n'
        '            xmlns:c="http://www.gtk.org/introspection/c/1.0"\n'
        '            xmlns:glib="http://www.gtk.org/introspection/glib/1.0">\n'
        '  <include name="GLib" version="2.0"/>\n'
        '  <namespace name="fontconfig" version="2.0"\n'
        '             c:identifier-prefixes="Fc"\n'
        '             c:symbol-prefixes="fc"/>\n'
        '</repository>\n')
