"""Linux-PAM —— 可插拔认证模块

https://github.com/linux-pam/linux-pam
许可证：BSD-3-Clause OR GPL-2.0-or-later

没有 PAM，login、su、sudo、屏幕锁、密码策略全部不成立。
系统只能以 root 直接进入——那不叫多用户系统。

Ubuntu 的整套认证栈都建在 PAM 上。我们不需要照搬 systemd，
但 PAM 是**所有**程序和认证之间的标准接口，绕不过去。

配置要点（不是可选项，每项都有真实事故对应）：
- pam_unix：本地口令认证，必须有
- pam_limits：资源限制，没有它 ulimit 不生效
- pam_env：登录环境变量
- pam_faillock：失败锁定。没有它，SSH 可以被无限次猜密码
- pam_pwquality：口令强度。没有它，用户可以设空口令
  或"123456"——而 shadow 本身不做强度检查
"""
from __future__ import annotations

name = "pam"
version = "1.7.0"
release = 1
summary = "可插拔认证模块（PAM）"
homepage = "https://github.com/linux-pam/linux-pam"
license = "BSD-3-Clause OR GPL-2.0-or-later"

source = ["https://ghproxy.net/https://github.com/linux-pam/linux-pam/releases/download/v1.7.0/Linux-PAM-1.7.0.tar.xz"]
sha256 = ["57dcd7a6b966ecd5bbd95e1d11173734691e16b68692fa59661cdae9b13b1697"]

depends = []
makedepends = ["flex", "bison"]
provides = ["pam"]

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    cf = ctx.meson_cross_file()
    x = f"--cross-file={cf}" if cf else ""
    ctx.run("mkdir -p build && cd build && meson setup .. --prefix=/usr --buildtype=release "
            f"{x} -Ddocs=disabled -Dexamples=false -Dpamlocking=false "
            "-Dselinux=disabled -Dlogind=disabled -Daudit=disabled")
    ctx.run("cd build && ninja")


def package(ctx):
    ctx.run("cd build && meson install --destdir {}".format(ctx.destdir))
    import os

    etc = os.path.join(ctx.destdir, "etc")
    os.makedirs(os.path.join(etc, "pam.d"), exist_ok=True)
    os.makedirs(os.path.join(etc, "security"), exist_ok=True)

    # 口令强度。没有它用户可以设空口令或"123456"，
    # 而 shadow 本身完全不做强度检查
    with open(os.path.join(etc, "security", "pwquality.conf"), "w") as f:
        f.write("""# 口令强度要求
minlen = 8
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
# 这些是下限不是建议：口令是唯一防线时，
# "123456" 和没设密码区别不大
""")

    # 资源限制。没有 pam_limits，ulimit 对登录会话不生效，
    # 一个 fork 炸弹就能拖死机器
    with open(os.path.join(etc, "security", "limits.conf"), "w") as f:
        f.write("""# 登录会话的资源限制（需要 pam_limits）
# 不设的话一个进程就能耗尽内存或文件描述符
*               soft    nofile          8192
*               hard    nofile          65536
*               soft    nproc           4096
*               hard    nproc           16384
""")
