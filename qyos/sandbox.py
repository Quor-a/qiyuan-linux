"""构建隔离。

两级隔离，按需启用：

  1. 环境净化（默认开启）：统一 PATH、清空宿主侵入变量、注入统一的编译参数。
  2. 命名空间（root 可用时自动开启）：mount/user/pid 命名空间，
     构建期默认断网（unshare -n），防止构建偷偷联网导致结果不可复现。

完整 chroot 到自建 rootfs 是第三级（自举之后才用得上），接口先留着。
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from . import util

# 统一的编译基线（加固项在这里一次定好，全系统生效）
BASE_CFLAGS = "-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wno-error -Wno-redundant-decls"
BASE_CXXFLAGS = BASE_CFLAGS
BASE_LDFLAGS = "-Wl,-z,relro,-z,now"


class Sandbox:
    def __init__(self, enable_ns: bool | None = None, enable_net: bool = False,
                 jobs: int | None = None):
        self.enable_net = enable_net
        self.jobs = jobs or max(1, os.cpu_count() or 1)
        if enable_ns is None:
            enable_ns = self._ns_available()
        self.enable_ns = enable_ns

    @staticmethod
    def _ns_available() -> bool:
        if os.geteuid() != 0:
            return False
        code, _ = util.run("unshare -m true", capture=True, check=False)
        return code == 0

    def env(self, extra: dict | None = None) -> dict:
        """构造净化的构建环境。"""
        env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/tmp",
            "TERM": os.environ.get("TERM", "dumb"),
            "LC_ALL": "C",
            "LANG": "C",
            "CC": "gcc",
            "CXX": "g++",
            "CFLAGS": BASE_CFLAGS,
            "CXXFLAGS": BASE_CXXFLAGS,
            "LDFLAGS": BASE_LDFLAGS,
            "MAKEFLAGS": f"-j{self.jobs}",
            "SOURCE_DATE_EPOCH": "1700000000",
            "QY_JOBS": str(self.jobs),
        }
        if extra:
            env.update(extra)
        return env

    def run(self, cmd: str, cwd: Path | None = None, env: dict | None = None,
            capture: bool = False, net: bool | None = None, check: bool = True):
        """在隔离环境中执行命令。"""
        full_env = self.env(env)
        use_net = self.enable_net if net is None else net
        prefix = ""
        if self.enable_ns and not use_net:
            # 断网命名空间；保留 mount ns 以便后续做只读挂载
            prefix = "unshare -m -n -r "
        elif self.enable_ns:
            prefix = "unshare -m -r "
        return util.run(prefix + cmd, cwd=cwd, env=full_env,
                        capture=capture, check=check)

    def describe(self) -> str:
        ns = "命名空间开" if self.enable_ns else "命名空间关"
        net = "允许联网" if self.enable_net else "默认断网"
        return f"{ns} / {net} / {self.jobs} 并行"


def mount_ro(src: Path, dst: Path) -> bool:
    """只读绑定挂载（自举后的 chroot 构建会用到）。"""
    dst.mkdir(parents=True, exist_ok=True)
    code, _ = util.run(f"mount --bind {src} {dst} && mount -o remount,ro {dst}",
                       capture=True, check=False)
    return code == 0


def umount_path(p: Path) -> bool:
    code, _ = util.run(f"umount -l {p}", capture=True, check=False)
    return code == 0
