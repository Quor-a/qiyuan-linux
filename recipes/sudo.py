"""sudo —— 权限提升

https://www.sudo.ws/
许可证：ISC

Ubuntu 默认禁用 root 登录，全部靠 sudo。
我们没有 sudo，且 su 依赖 PAM——两项叠加等于没有权限模型。

没有 sudo 的实际后果不是"不方便"，是安全事故：
用户只能全程以 root 操作，一次误删就毁掉系统，
而且没有任何审计记录能看出是谁干的。

sudoers 默认配置里几条必须做对的：
- root 全权限（否则救援时束手束脚）
- %wheel 组全权限（Ubuntu 用 sudo 组，我们用 wheel）
- **requiretty 不能开**：开了之后脚本和自动化全部失效，
  而这恰恰是服务器场景的主要用法
- env_reset 必须开：不清环境变量的话，
  攻击者可以通过 LD_PRELOAD 之类提权
- 日志必须开：没有日志的 sudo 等于没有审计
"""
from __future__ import annotations

name = "sudo"
version = "1.9.17p1"
release = 1
summary = "以其他用户身份执行命令（权限提升）"
homepage = "https://www.sudo.ws/"
license = "ISC"

source = ["https://www.sudo.ws/dist/sudo-1.9.17p1.tar.gz"]
sha256 = ["ff607ea717072197738a78f778692cd6df9a7e3e404565f51de063ca27455d32"]

depends = ["pam"]
makedepends = ["pam"]
provides = ["sudo"]
# 装 sudo 之前必须先有 PAM：没有 PAM 的 sudo 编译不出来，
# 勉强编出来也无法做口令认证
requires_build_machine = True
network = False
compression = "gz"

# wheel 组的用户可以用 sudo。装机时把管理员加进这个组
ADMIN_GROUP = "wheel"


def build(ctx):
    ctx.run("./configure" + " " .join(ctx.configure_args()) + " --prefix=/usr --disable-makeinstall-chown --disable-makeinstall-root"
            " --sbindir=/usr/sbin"
            " --libexecdir=/usr/lib"
            " --with-pam"
            " --with-env-editor"
            " --with-logfac=auth"
            " --with-secure-path=/usr/sbin:/usr/bin:/sbin:/bin"
            " --disable-static")
    ctx.run("make")


def package(ctx):
    import shutil, os
    if os.path.isdir("dest"):
        shutil.rmtree("dest")
    ctx.run("make DESTDIR={} INSTALL_OWNER= install".format(ctx.destdir))
    import os

    # 默认 sudoers。没有它 sudo 装了也用不了——
    # 而且报错是"用户不在 sudoers 文件中"，
    # 新手看到这个会以为是自己的问题
    etc = os.path.join(ctx.destdir, "etc")
    os.makedirs(os.path.join(etc, "sudoers.d"), exist_ok=True)
    spath = os.path.join(etc, "sudoers")
    if os.path.exists(spath):
        os.chmod(spath, 0o644)
        os.remove(spath)
    with open(spath, "w") as f:
        f.write("""# 默认 sudoers 规则
# 修改请用 visudo —— 直接编辑写错了会让整个系统无法提权，
# 而修复需要进救援模式

root ALL=(ALL:ALL) ALL

# wheel 组成员可以提权。装机时把管理员账号加进这个组：
#   usermod -aG wheel <用户名>
%{group} ALL=(ALL:ALL) ALL

# 环境变量必须重置。不清的话攻击者可以通过
# LD_PRELOAD、PATH 之类在提权时夹带自己的代码
Defaults env_reset
Defaults secure_path="/usr/sbin:/usr/bin:/sbin:/bin"

# 必须留日志。没有日志的 sudo 等于没有审计——
# 出事后无法知道是谁执行了那条命令
Defaults logfile="/var/log/sudo.log"
Defaults log_input, log_output
Defaults!{group} lecture="once"

# 不能开 requiretty：开了之后脚本、cron、远程自动化全部失效，
# 而服务器场景主要就是这么用 sudo 的
# Defaults requiretty
""".format(group=ADMIN_GROUP))
