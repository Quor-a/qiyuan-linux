"""freetype —— 字体渲染引擎


许可证：GPL-2.0-or-later OR FTL
"""

name = "freetype"
version = "2.13.3"
release = 1
summary = "字体渲染引擎"
homepage = ""
license = "GPL-2.0-or-later OR FTL"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums freetype
source = ["https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz"]
sha256 = ["0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289"]

depends = ["zlib", "libpng", "brotli"]
makedepends = ["zlib", "libpng", "brotli"]
provides = []

# cairo → fontconfig → freetype → harfbuzz → cairo 这个环里，断在 freetype
# 这一侧：harfbuzz 对 freetype 而言是"复杂文本塑形"而非"能跑"的依赖。
# 先编一个不带 harfbuzz 的 freetype（能渲染基本字形），用它编出 harfbuzz，
# 然后 freetype 必须重编——否则发布出去的 freetype 对中文/阿拉伯文
# 连字与塑形是错的，而这种情况能跑能过测试，极难发现。
cycle_break = ["harfbuzz"]

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("./configure " + " ".join(ctx.configure_args()) + " --prefix=/usr --enable-freetype-config --disable-static")
    ctx.run("make")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
    # harfbuzz 的 introspection 需要 freetype2-2.0.gir（upstream freetype
    # 不生成 gir，这里用最小手写版满足 g-ir-scanner 的 include 解析；
    # 只有当 g-ir-scanner 可用时才有意义）。
    import shutil
    if shutil.which("g-ir-scanner") is None:
        return
    gir = ctx.destdir / "usr" / "share" / "gir-1.0"
    gir.mkdir(parents=True, exist_ok=True)
    (gir / "freetype2-2.0.gir").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<repository version="1.2"\n'
        '            xmlns="http://www.gtk.org/introspection/core/1.0"\n'
        '            xmlns:c="http://www.gtk.org/introspection/c/1.0"\n'
        '            xmlns:glib="http://www.gtk.org/introspection/glib/1.0">\n'
        '  <include name="GLib" version="2.0"/>\n'
        '  <namespace name="freetype2" version="2.0"\n'
        '             c:identifier-prefixes="FT"\n'
        '             c:symbol-prefixes="ft"/>\n'
        '</repository>\n')
