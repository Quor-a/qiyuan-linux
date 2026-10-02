"""wpa_supplicant —— WPA/WPA2/WPA3 无线认证

https://w1.fi/wpa_supplicant/
许可证：BSD-3-Clause

笔记本连 WiFi 的唯一途径。没有它配合固件，无线彻底不可用。
iwd 是更现代的替代品（内核原生、更省资源），两者都提供，
装机时可选；默认装 wpa_supplicant（NetworkManager 支持最成熟）。

WPA3（SAE）与 OWE 必须开：
- SAE 是 WPA3 个人版，能抗离线字典攻击；
  不开的话连 WPA3 网络会直接失败，而报错是"认证失败"，
  看不出是我们没编译支持
- OWE 是开放网络的加密（ Opportunistic Wireless Encryption），
  不开的话咖啡厅这类开放 WiFi 是明文传输
"""
from __future__ import annotations

name = "wpa_supplicant"
version = "2.11"
release = 1
summary = "WPA/WPA2/WPA3 无线认证与漫游"
homepage = "https://w1.fi/wpa_supplicant/"
license = "BSD-3-Clause"

source = ["https://w1.fi/releases/wpa_supplicant-2.11.tar.gz"]
sha256 = ["912ea06f74e30a8e36fbb68064d6cdff218d8d591db0fc5d75dee6c81ac7fc0a"]

depends = ["openssl", "libnl", "dbus"]
makedepends = ["pkgconf", "openssl", "libnl", "dbus"]
provides = ["wifi-supplicant"]
requires_build_machine = True
network = False
compression = "gz"

config_files = ["etc/wpa_supplicant/wpa_supplicant.conf"]

# 追加到上游 defconfig 之上的选项。
# 完全手写 .config 会漏掉几十个必需项，所以只做增量
EXTRA_CONFIG = """CONFIG_IEEE80211N=y
CONFIG_IEEE80211AC=y
CONFIG_IEEE80211AX=y
CONFIG_SAE=y
CONFIG_OWE=y
CONFIG_WPS=n
CONFIG_EAP=y
CONFIG_CTRL_IFACE_DBUS_NEW=y
CONFIG_DEBUG_SYSLOG=y
"""


def build(ctx):
    import os

    src = os.path.join(ctx.srcdir, "wpa_supplicant")
    cfg = os.path.join(src, ".config")
    ctx.run("cp {}/defconfig {}".format(src, cfg))
    with open(cfg, "a") as f:
        f.write(EXTRA_CONFIG)
    ctx.run("cd wpa_supplicant && make BINDIR=/usr/bin LIBDIR=/usr/lib")


def package(ctx):
    import os

    ctx.run("cd wpa_supplicant && make DESTDIR={} install".format(ctx.destdir))
    d = os.path.join(ctx.destdir, "etc", "wpa_supplicant")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "wpa_supplicant.conf"), "w") as f:
        f.write("""# 由启元 Linux 生成
ctrl_interface=/run/wpa_supplicant
ctrl_interface_group=0
update_config=1
country=CN
""")
