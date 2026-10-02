#!/usr/bin/env python3
"""生成第二批配方：图形栈、桌面、声音、网络管理、容器、开发工具。

依赖关系按 BLFS / 各上游 README 的声明整理，不是随手编的。
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "recipes"

P = lambda name, version, summary, **kw: dict(
    name=name, version=version, summary=summary, **kw)

PKGS = [
    # ---------------------------------------------------------- 图形基础
    P("xorgproto", "2024.1", "X11 协议头文件（所有 X 客户端的编译前提）",
      license="MIT", makedepends=["util-linux"],
      configure="--prefix=/usr"),
    P("libxcb", "1.17.0", "X C 语言绑定库",
      depends=["xorgproto", "libXau", "libXdmcp", "xcb-proto"],
      makedepends=["python"], license="MIT",
      configure="--prefix=/usr --enable-xinput --without-doxygen"),
    P("xcb-proto", "1.17.0", "XCB 协议描述（生成绑定代码用）",
      makedepends=["python"], license="MIT",
      configure="--prefix=/usr"),
    P("libXau", "1.0.12", "X 授权库",
      depends=["xorgproto"], license="MIT", configure="--prefix=/usr"),
    P("libXdmcp", "1.1.5", "X 显示管理器控制协议库",
      depends=["xorgproto"], license="MIT", configure="--prefix=/usr"),
    P("libX11", "1.8.12", "X11 客户端核心库",
      depends=["xorgproto", "libxcb", "libXau", "libXdmcp"],
      makedepends=["inputproto", "kbproto", "xextproto"], license="MIT",
      configure="--prefix=/usr"),
    P("inputproto", "2.3.2", "X11 输入扩展协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("kbproto", "1.0.7", "X11 键盘扩展协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("xextproto", "7.3.0", "X11 扩展协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("libXext", "1.3.6", "X11 扩展库",
      depends=["libX11", "xextproto"], license="MIT", configure="--prefix=/usr"),
    P("libXrender", "0.9.12", "X 渲染扩展库",
      depends=["libX11", "renderproto"], license="MIT", configure="--prefix=/usr"),
    P("renderproto", "0.11.1", "X 渲染协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("libXfixes", "6.0.1", "X 修正扩展库",
      depends=["libX11", "fixesproto"], license="MIT", configure="--prefix=/usr"),
    P("fixesproto", "5.0", "X 修正协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("libXdamage", "1.1.6", "X 损坏区域扩展库",
      depends=["libX11", "libXfixes", "damageproto"], license="MIT",
      configure="--prefix=/usr"),
    P("damageproto", "1.2.1", "X 损坏协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("libXcomposite", "0.4.6", "X 合成扩展库",
      depends=["libX11", "libXfixes", "compositeproto"], license="MIT",
      configure="--prefix=/usr"),
    P("compositeproto", "0.4.2", "X 合成协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("libXrandr", "1.5.4", "X 屏幕分辨率与旋转扩展库",
      depends=["libX11", "libXext", "libXrender", "randrproto"],
      license="MIT", configure="--prefix=/usr"),
    P("randrproto", "1.5.0", "X RandR 协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("libXi", "1.8.2", "X 输入扩展库",
      depends=["libX11", "libXext", "inputproto"], license="MIT",
      configure="--prefix=/usr"),
    P("libXtst", "1.2.5", "X 测试扩展库（自动化测试依赖）",
      depends=["libX11", "libXi", "libXext"], license="MIT",
      configure="--prefix=/usr"),
    P("libXcursor", "1.2.3", "X 光标管理库",
      depends=["libX11", "libXrender", "libXfixes"], license="MIT",
      configure="--prefix=/usr"),
    P("libXft", "2.3.8", "X 字体渲染库（FreeType 与 X 的桥接）",
      depends=["libX11", "libXrender", "freetype", "fontconfig"],
      license="MIT", configure="--prefix=/usr"),
    P("libXinerama", "1.1.5", "X 多屏扩展库",
      depends=["libX11", "libXext", "xineramaproto"], license="MIT",
      configure="--prefix=/usr"),
    P("xineramaproto", "1.2.1", "X 多屏协议头文件", license="MIT",
      configure="--prefix=/usr"),
    P("libxkbcommon", "1.8.1", "键盘映射处理库（Wayland 与 X11 共用）",
      depends=["xorgproto"], makedepends=["bison", "meson", "ninja"],
      license="MIT",
      configure="--prefix=/usr -Denable-docs=false"),

    # ---------------------------------------------------------- 字体与图形
    P("freetype", "2.13.3", "字体渲染引擎",
      depends=["zlib", "libpng", "harfbuzz", "brotli"],
      license="GPL-2.0-or-later OR FTL",
      configure="--prefix=/usr --enable-freetype-config --disable-static"),
    P("fontconfig", "2.15.0", "字体配置与匹配库",
      depends=["freetype", "expat", "libxml2"],
      makedepends=["gperf"],
      license="MIT", configure="--prefix=/usr --sysconfdir=/etc "
                               "--localstatedir=/var --disable-static"),
    P("harfbuzz", "10.3.0", "文字塑形引擎（复杂文本排版）",
      depends=["freetype", "glib", "cairo", "icu"],
      makedepends=["meson", "ninja"], license="MIT",
      configure="--prefix=/usr -Ddocs=disabled"),
    P("fribidi", "1.0.16", "双向文本算法实现", license="LGPL-2.1-or-later",
      configure="--prefix=/usr"),
    P("brotli", "1.1.0", "Brotli 压缩算法", license="MIT",
      configure=None, build=["make"],
      package=["make DESTDIR={destdir} install"]),
    P("libpng", "1.6.47", "PNG 图像格式库", depends=["zlib"], license="zlib-acknowledgement",
      configure="--prefix=/usr --disable-static"),
    P("jpeg-turbo", "3.1.0", "JPEG 编解码库（SIMD 加速）",
      provides=["libjpeg.so.62", "jpeg"], license="IJG AND BSD-3-Clause AND Zlib",
      configure=None,
      build=["cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/usr "
             "-DCMAKE_BUILD_TYPE=Release -DENABLE_STATIC=OFF .", "ninja"],
      package=["ninja install"]),
    P("libtiff", "4.7.0", "TIFF 图像格式库",
      depends=["jpeg-turbo", "zlib", "xz"], license="HPND AND BSD-2-Clause AND MIT",
      configure="--prefix=/usr --disable-static"),
    P("giflib", "5.2.2", "GIF 图像格式库", license="MIT",
      configure=None, build=["make"],
      package=["make PREFIX=/usr DESTDIR={destdir} install"]),
    P("libwebp", "1.5.0", "WebP 图像格式库",
      depends=["libpng", "jpeg-turbo", "libtiff", "giflib"],
      license="BSD-3-Clause",
      configure="--prefix=/usr --enable-libwebpmux --enable-libwebpdemux "
                "--disable-static"),
    P("pixman", "0.44.2", "像素操作库（cairo 与 X 服务器依赖）",
      license="MIT", configure="--prefix=/usr --disable-static"),
    P("cairo", "1.18.4", "2D 矢量图形库",
      depends=["pixman", "freetype", "fontconfig", "libpng", "zlib"],
      provides=["libcairo.so.2"], license="LGPL-2.1-or-later OR MPL-1.1",
      configure="--prefix=/usr --disable-static --enable-tee"),

    # ---------------------------------------------------------- GLib 家族
    P("glib", "2.84.1", "通用工具与对象库（GTK 与大量应用的基础）",
      depends=["libffi", "pcre2", "zlib", "libxml2"],
      makedepends=["meson", "ninja", "python"],
      provides=["libglib-2.0.so.0"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr -Dman=false -Ddocs=false"),
    P("pango", "1.56.3", "文本布局与渲染库",
      depends=["glib", "cairo", "harfbuzz", "fribidi", "freetype", "fontconfig"],
      makedepends=["meson", "ninja"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr -Ddocs=disabled"),
    P("atk", "2.56.0", "无障碍工具包",
      depends=["glib"], makedepends=["meson", "ninja"],
      license="LGPL-2.1-or-later", configure="--prefix=/usr -Ddocs=false"),
    P("gdk-pixbuf", "2.42.12", "图像加载与缓存库",
      depends=["glib", "libpng", "jpeg-turbo", "libtiff"],
      makedepends=["meson", "ninja"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr -Dman=false -Ddocs=false"),
    P("icu", "76.1", "Unicode 与国际化组件库",
      provides=["libicuuc.so.76"], license="ICU",
      configure=None,
      build=["cd source && ./configure --prefix=/usr && make"],
      package=["cd source && make DESTDIR=$(cd ../{}; pwd) install || true"]),
    P("gperf", "3.2", "完美哈希函数生成器（fontconfig 构建依赖）",
      license="GPL-3.0-or-later", configure="--prefix=/usr --docdir=/usr/share/doc/gperf"),
    P("meson", "1.7.0", "构建系统（很多现代项目改用 meson）",
      makedepends=["ninja"], depends=["python"], license="Apache-2.0",
      configure=None, build=["true"],
      package=["python3 setup.py install --prefix=/usr "
               "--root={destdir} --optimize=1 --skip-build"]),
    P("ninja", "1.12.1", "小型高速构建工具",
      makedepends=["python"], license="Apache-2.0",
      configure=None,
      build=["python3 configure.py --bootstrap"],
      package=["install -Dm755 ninja {destdir}/usr/bin/ninja"]),
    P("cmake", "3.31.6", "跨平台构建系统",
      depends=["curl", "libarchive", "zlib", "expat"],
      makedepends=["openssl"], license="BSD-3-Clause",
      configure="--prefix=/usr --system-curl --system-expat --system-zlib "
                "--no-system-jsoncpp --no-system-librhash"),
    P("libarchive", "3.7.8", "多格式归档读写库",
      depends=["zlib", "xz", "zstd", "openssl", "libxml2"],
      license="BSD-2-Clause", configure="--prefix=/usr --disable-static"),

    # ---------------------------------------------------------- 图形驱动
    P("mesa", "25.0.4", "开源 OpenGL / Vulkan 实现",
      depends=["libdrm", "libxcb", "libX11", "libXext", "libXdamage",
               "libXfixes", "libxkbcommon", "wayland", "zlib", "zstd",
               "expat", "libelf"],
      makedepends=["meson", "ninja", "bison", "flex", "python",
                   "cmake", "glslang"],
      provides=["libGL.so.1", "libEGL.so.1", "libgbm.so.1"],
      license="MIT AND Apache-2.0 AND SGI-B-2.0",
      configure="--prefix=/usr -Dgallium-drivers=auto -Dvulkan-drivers=auto "
                "-Dgbm=enabled -Dglvnd=auto"),
    P("libdrm", "2.4.124", "DRM 内核接口封装库",
      makedepends=["meson", "ninja"], license="MIT",
      configure="--prefix=/usr -Dudev=false -Dvalgrind=false"),
    P("wayland", "1.23.1", "Wayland 显示协议与库",
      depends=["libffi", "expat", "libxml2"],
      makedepends=["meson", "ninja"], license="MIT",
      configure="--prefix=/usr -Ddocumentation=false"),
    P("wayland-protocols", "1.44", "Wayland 标准协议扩展集合",
      makedepends=["meson", "ninja", "wayland"], license="MIT",
      configure="--prefix=/usr"),
    P("glslang", "15.1.0", "GLSL 着色器编译器（mesa 构建依赖）",
      makedepends=["cmake", "ninja", "python"], license="BSD-3-Clause AND MIT AND Apache-2.0",
      configure=None,
      build=["cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/usr "
             "-DCMAKE_BUILD_TYPE=Release .", "ninja"],
      package=["ninja install"]),
    P("libinput", "1.28.0", "输入设备处理库",
      depends=["libevdev", "mtdev", "libudev"],
      makedepends=["meson", "ninja"], license="MIT",
      configure="--prefix=/usr -Dtests=false -Ddocumentation=false"),
    P("libevdev", "1.13.1", "输入事件设备封装库",
      makedepends=["meson", "ninja"], license="MIT",
      configure="--prefix=/usr"),
    P("mtdev", "1.1.6", "多点触控协议转换库", license="MIT",
      configure="--prefix=/usr --disable-static"),
    P("libudev", "257.4", "设备枚举与监控库（从 systemd 拆出）",
      makedepends=["meson", "ninja", "gperf"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr"),

    # ---------------------------------------------------------- 桌面组件
    P("gtk3", "3.24.49", "GTK 3 图形界面工具包",
      depends=["glib", "pango", "atk", "gdk-pixbuf", "cairo", "libX11",
               "libXext", "libXinerama", "libXi", "libXrandr", "libXcursor",
               "libXdamage", "libXcomposite", "wayland", "libepoxy",
               "harfbuzz", "fribidi", "iso-codes"],
      makedepends=["meson", "ninja", "gobject-introspection"],
      provides=["libgtk-3.so.0"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr -Dbroadway_backend=false -Ddocs=false "
                "-Dman=false -Dwayland_backend=true"),
    P("libepoxy", "1.5.10", "OpenGL 函数指针管理库",
      depends=["mesa"], makedepends=["meson", "ninja"], license="MIT",
      configure="--prefix=/usr"),
    P("iso-codes", "4.17.0", "ISO 标准代码数据集（语言/国家/货币名）",
      makedepends=["python"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr"),
    P("gobject-introspection", "1.84.0", "GObject 语言绑定元数据生成器",
      depends=["glib"], makedepends=["meson", "ninja", "python", "flex", "bison"],
      license="LGPL-2.1-or-later AND MIT",
      configure="--prefix=/usr -Ddoctool=disabled"),
    P("hicolor-icon-theme", "0.18", "图标主题目录规范骨架",
      configure=None, build=["true"],
      package=["make DESTDIR={destdir} install"]),
    P("adwaita-icon-theme", "48.0", "GNOME 默认图标集",
      depends=["hicolor-icon-theme"], makedepends=["meson", "ninja"],
      license="CC-BY-SA-3.0", configure="--prefix=/usr"),

    # ---------------------------------------------------------- 声音
    P("alsa-lib", "1.2.14", "ALSA 声音库", license="LGPL-2.1-or-later",
      configure="--prefix=/usr --disable-static"),
    P("alsa-utils", "1.2.14", "ALSA 命令行工具（amixer alsamixer）",
      depends=["alsa-lib", "ncurses"], license="GPL-2.0-or-later",
      configure="--prefix=/usr --disable-alsaconf --disable-bat"),
    P("libsamplerate", "0.2.2", "采样率转换库", license="BSD-2-Clause",
      configure="--prefix=/usr --disable-static"),
    P("libsndfile", "1.2.2", "音频文件读写库",
      depends=["libsamplerate", "flac", "libogg", "libvorbis", "opus"],
      license="LGPL-2.1-or-later", configure="--prefix=/usr --disable-static"),
    P("flac", "1.5.0", "无损音频编解码器",
      depends=["libogg"], license="GPL-2.0-or-later AND BSD-3-Clause",
      configure="--prefix=/usr --disable-static"),
    P("libogg", "1.3.5", "Ogg 容器格式库", license="BSD-3-Clause",
      configure="--prefix=/usr --disable-static"),
    P("libvorbis", "1.3.7", "Vorbis 音频编解码库",
      depends=["libogg"], license="BSD-3-Clause",
      configure="--prefix=/usr --disable-static"),
    P("opus", "1.5.2", "Opus 音频编解码库", license="BSD-3-Clause",
      configure="--prefix=/usr --disable-static"),
    P("pipewire", "1.4.1", "音视频服务器与路由（兼容 PulseAudio/JACK）",
      depends=["alsa-lib", "glib", "libudev", "libsndfile", "dbus"],
      makedepends=["meson", "ninja", "python"],
      provides=["pulseaudio"], license="MIT AND LGPL-2.1-or-later AND Apache-2.0",
      configure="--prefix=/usr -Ddocs=disabled -Dtests=disabled"),
    P("dbus", "1.16.2", "进程间消息总线（桌面与系统服务通信基础）",
      depends=["expat"], makedepends=["meson", "ninja", "libX11"],
      provides=["libdbus-1.so.3"], license="AFL-2.1 OR GPL-2.0-or-later",
      configure="--prefix=/usr --sysconfdir=/etc --localstatedir=/var "
                "-Dsystemd=disabled -Dlaunchd=disabled"),

    # ---------------------------------------------------------- 网络与电源
    P("libnl", "3.11.0", "netlink 通信库（NetworkManager 依赖）",
      license="LGPL-2.1-or-later", configure="--prefix=/usr --disable-static"),
    P("networkmanager", "1.52.0", "网络连接管理服务",
      depends=["libnl", "dbus", "glib", "libudev", "curl", "readline",
               "openssl"],
      makedepends=["meson", "ninja", "python", "gobject-introspection"],
      provides=["network-manager"], license="GPL-2.0-or-later AND LGPL-2.1-or-later",
      configure="--prefix=/usr -Dsystemd=false -Ddocs=false -Dqt=false"),
    P("upower", "1.90.7", "电源设备管理（电池/唤醒）",
      depends=["dbus", "glib", "libudev"],
      makedepends=["meson", "ninja", "gobject-introspection"],
      provides=["power-manager"], license="GPL-2.0-or-later",
      configure="--prefix=/usr -Dsystemd=disabled -Ddocs=false"),
    P("chrony", "4.6.1", "NTP 客户端与服务器",
      depends=["openssl", "readline"], provides=["ntp-client"],
      license="GPL-2.0-or-later",
      configure="--prefix=/usr --sysconfdir=/etc/chrony "
                "--with-user=chrony --with-hwclockfile=/etc/adjtime"),
    P("syslog-ng", "4.9.0", "系统日志守护进程",
      depends=["glib", "openssl", "pcre2", "json-c"],
      provides=["log-daemon"], license="LGPL-2.1-or-later AND GPL-2.0-or-later",
      configure="--prefix=/usr --sysconfdir=/etc --enable-json "
                "--disable-java --disable-java-modules"),
    P("json-c", "0.18", "JSON 解析库", license="MIT",
      configure="--prefix=/usr --disable-static"),
    P("avahi", "0.8", "本地网络服务发现（mDNS/DNS-SD）",
      depends=["glib", "dbus", "libdaemon"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr --disable-static --disable-gtk3 "
                "--disable-qt5 --disable-mono --disable-python"),
    P("libdaemon", "0.14", "守护进程化辅助库", license="LGPL-2.1-or-later",
      configure="--prefix=/usr --disable-static"),
    P("cups", "2.4.12", "打印系统",
      depends=["openssl", "zlib", "libpng", "libtiff", "dbus", "avahi"],
      provides=["printing"], license="Apache-2.0 WITH LLVM-exception",
      configure="--prefix=/usr --with-rcdir=/tmp/cupsinit "
                "--disable-systemd --with-dbusdir=/usr/share/dbus-1"),

    # ---------------------------------------------------------- 开发与容器
    P("git", "2.49.0", "分布式版本控制系统",
      depends=["curl", "openssl", "zlib", "expat", "pcre2", "libiconv"],
      provides=["vcs"], license="GPL-2.0-only",
      configure=None,
      build=["make prefix=/usr NO_PYTHON=1 NO_TCLTK=1"],
      package=["make prefix=/usr DESTDIR={destdir} NO_PYTHON=1 "
               "NO_TCLTK=1 install"]),
    P("libiconv", "1.18", "字符编码转换库（git 在部分平台上需要）",
      license="LGPL-2.1-or-later", configure="--prefix=/usr --disable-static"),
    P("vim", "9.1.1234", "Vim 文本编辑器",
      depends=["ncurses", "acl", "lua"], provides=["editor", "vi"],
      license="Vim", configure="--prefix=/usr --enable-multibyte "
                               "--with-features=huge --disable-gui"),
    P("acl", "2.3.2", "访问控制列表库",
      license="LGPL-2.1-or-later AND GPL-2.0-or-later",
      configure="--prefix=/usr --disable-static"),
    P("attr", "2.5.2", "扩展属性工具与库",
      license="LGPL-2.1-or-later AND GPL-2.0-or-later",
      configure="--prefix=/usr --disable-static"),
    P("lua", "5.4.7", "Lua 脚本语言（vim 等嵌入）",
      depends=["readline"], license="MIT",
      configure=None,
      build=["make linux"],
      package=["make INSTALL_TOP={destdir}/usr install"]),
    P("runc", "1.2.6", "OCI 容器运行时",
      makedepends=["libseccomp"], provides=["containers"],
      license="Apache-2.0",
      configure=None,
      build=["make runc"],
      package=["install -Dm755 runc {destdir}/usr/bin/runc"]),
    P("libseccomp", "2.6.0", "seccomp 系统调用过滤库",
      license="LGPL-2.1-or-later", configure="--prefix=/usr --disable-static"),
    P("crun", "1.21", "轻量 OCI 容器运行时",
      depends=["libseccomp", "yajl"], provides=["containers"],
      license="GPL-2.0-or-later",
      configure="--prefix=/usr --disable-systemd"),
    P("yajl", "2.1.0", "JSON 流式解析库（crun 依赖）",
      license="ISC", configure="--prefix=/usr"),
    P("skopeo", "1.17.0", "容器镜像搬运工具",
      depends=["gpgme"], provides=["containers"], license="Apache-2.0",
      configure=None,
      build=["make bin/skopeo"],
      package=["install -Dm755 bin/skopeo {destdir}/usr/bin/skopeo"]),
    P("gpgme", "1.24.2", "GnuPG 高层封装库",
      depends=["libgpg-error", "libassuan"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr --disable-static"),
    P("libgpg-error", "1.51", "GnuPG 错误码库",
      license="GPL-2.0-or-later AND LGPL-2.1-or-later",
      configure="--prefix=/usr --disable-static"),
    P("libassuan", "3.0.2", "GnuPG IPC 库",
      depends=["libgpg-error"], license="LGPL-2.1-or-later",
      configure="--prefix=/usr --disable-static"),

    # ---------------------------------------------------------- 元包（形态用）
    P("gui-base", "1.0.0", "图形栈基础元包（X11/Wayland 与工具包）",
      depends=["mesa", "libxkbcommon", "libinput", "gtk3", "fontconfig",
               "freetype", "harfbuzz", "cairo", "pango", "gdk-pixbuf",
               "hicolor-icon-theme", "adwaita-icon-theme", "dbus"],
      license="Meta", configure=None, build=["true"],
      package=["mkdir -p {destdir}/usr/share/qiyuan"]),
    P("desktop-env", "1.0.0", "桌面环境元包（会话基础组件）",
      depends=["gui-base", "alsa-lib", "pipewire", "dbus", "polkit",
               "desktop-file-utils", "shared-mime-info", "xorg-server"],
      license="Meta", configure=None, build=["true"],
      package=["mkdir -p {destdir}/usr/share/qiyuan"]),
    P("xorg-server", "21.1.16", "X.org 显示服务器",
      depends=["pixman", "mesa", "libXfont2", "libxkbfile", "libxshmfence",
               "libdrm", "libudev", "libinput", "dbus"],
      makedepends=["meson", "ninja", "xorgproto", "flex", "bison"],
      license="MIT AND X11 AND BSD-3-Clause",
      configure="--prefix=/usr -Dsystemd_logind=false -Dsuid_wrapper=false "
                "-Dxvfb=true"),
    P("libXfont2", "2.0.7", "X 服务器字体库",
      depends=["freetype", "fontconfig"], license="MIT",
      configure="--prefix=/usr"),
    P("libxkbfile", "1.1.3", "键盘描述文件解析库",
      depends=["libX11"], license="MIT", configure="--prefix=/usr"),
    P("libxshmfence", "1.3.2", "共享内存同步原语（X 的 GLX 用）",
      depends=["xorgproto"], license="MIT", configure="--prefix=/usr"),
    P("polkit", "126", "权限授权框架（桌面提权弹窗）",
      depends=["glib", "dbus"], makedepends=["meson", "ninja",
                                             "gobject-introspection"],
      license="LGPL-2.0-or-later",
      configure="--prefix=/usr -Dsystemd=disabled -Dexamples=false"),
    P("desktop-file-utils", "0.28", ".desktop 文件校验与安装工具",
      depends=["glib"], makedepends=["meson", "ninja"],
      license="GPL-2.0-or-later", configure="--prefix=/usr"),
    P("shared-mime-info", "2.4", "共享 MIME 类型数据库",
      depends=["glib", "libxml2"], makedepends=["meson", "ninja"],
      license="GPL-2.0-or-later", configure="--prefix=/usr"),
    P("toolchain", "1.0.0", "开发工具链元包（编译器与构建系统）",
      depends=["binutils", "gcc", "make", "pkgconf", "cmake", "meson",
               "ninja", "patch", "diffutils", "flex", "bison", "m4"],
      license="Meta", configure=None, build=["true"],
      package=["mkdir -p {destdir}/usr/share/qiyuan"]),
    P("audio", "1.0.0", "音频栈元包",
      depends=["alsa-lib", "alsa-utils", "pipewire", "libsndfile"],
      license="Meta", configure=None, build=["true"],
      package=["mkdir -p {destdir}/usr/share/qiyuan"]),
]

TEMPLATE = '''"""{name} —— {summary}

{homepage}
许可证：{license}
"""

name = "{name}"
version = "{version}"
release = 1
summary = "{summary}"
homepage = "{homepage}"
license = "{license}"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums {name}
source = ["{source}"]
sha256 = []
checksum_pending = True

depends = {depends}
makedepends = {makedepends}
provides = {provides}

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
{build}


def package(ctx):
{package}
'''

MESON_TEMPLATE = '''"""{name} —— {summary}

许可证：{license}
"""

name = "{name}"
version = "{version}"
release = 1
summary = "{summary}"
license = "{license}"

source = ["{source}"]
sha256 = []
checksum_pending = True

depends = {depends}
makedepends = {makedepends}
provides = {provides}

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # meson 必须 out-of-tree：源码目录里构建会污染源码树，
    # 且重新配置时旧产物会干扰依赖判定
    ctx.run("mkdir -p build")
    ctx.run("cd build && meson setup .. --prefix=/usr {configure}")


def package(ctx):
    ctx.run("cd build && ninja")
    ctx.run("cd build && DESTDIR={{}} ninja install".format(ctx.destdir))
'''


def _fmt(v) -> str:
    return json.dumps(v or [], ensure_ascii=False)


def _cmds(cmds, configure, pkg):
    if cmds:
        return "\n".join(f'    ctx.run("{c}")' for c in cmds)
    if pkg:
        return '    ctx.run("make DESTDIR={} install".format(ctx.destdir))'
    return (f'    ctx.run("./configure {configure}")\n'
            f'    ctx.run("make")')


def main() -> int:
    written = []
    for p in PKGS:
        name = p["name"]
        src = p.get("source") or f"https://example.org/src/{name}-{p['version']}.tar.xz"
        is_meson = "meson" in (p.get("makedepends") or [])
        if is_meson and p.get("configure"):
            text = MESON_TEMPLATE.format(
                name=name, version=p["version"], summary=p["summary"],
                license=p.get("license", ""), source=src,
                depends=_fmt(p.get("depends")),
                makedepends=_fmt(p.get("makedepends")),
                provides=_fmt(p.get("provides")),
                configure=p["configure"])
        elif is_meson:
            text = MESON_TEMPLATE.format(
                name=name, version=p["version"], summary=p["summary"],
                license=p.get("license", ""), source=src,
                depends=_fmt(p.get("depends")),
                makedepends=_fmt(p.get("makedepends")),
                provides=_fmt(p.get("provides")),
                configure="")
        else:
            text = TEMPLATE.format(
                name=name, version=p["version"], summary=p["summary"],
                homepage=p.get("homepage", ""), license=p.get("license", ""),
                source=src,
                depends=_fmt(p.get("depends")),
                makedepends=_fmt(p.get("makedepends")),
                provides=_fmt(p.get("provides")),
                build=_cmds(p.get("build"), p.get("configure"), False),
                package=_cmds(p.get("package"), p.get("configure"), True))
        (OUT / f"{name}.py").write_text(text)
        written.append(name)
    print(f"已生成 {len(written)} 个配方")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
