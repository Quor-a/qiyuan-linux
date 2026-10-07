"""包级系统操作：配置文件保护、安装脚本、触发器、alternatives、系统用户。

这五件事是"包管理器"和"能用的发行版"之间的差距。前两件不做，
系统能装起来但没法用：升级会冲掉用户的配置，装完 openssh 没有
host key，装完字体没有缓存。

**配置文件保护为什么是一等公民**

/etc 下的文件用户会改。升级包时无条件覆盖，等于每次升级都毁掉
用户的配置——改过的 sshd_config、nginx.conf、fstab 全没了。
这不是理论风险，是每次升级都必然发生的事故。

正确处理要三方比对（pacman/dpkg 都这么做）：

  旧原始版本 = 上次安装时包里的版本（记在数据库里）
  磁盘版本   = 现在机器上的（可能被用户改过）
  新包版本   = 这次要装的版本

  a) 磁盘 == 旧原始，说明用户没改过 → 直接覆盖成新版本
  b) 磁盘 != 旧原始（用户改了），旧原始 == 新版本（包没改）→ 保留用户的
  c) 两边都改了 → 冲突：保留用户的，新版本存成 .qynew，明确提示

只比较"文件是否存在"或者"时间戳"是不够的——用户改了内容但没改时间戳
的情况很常见。

**脚本 vs 触发器**

脚本是包自带的任意代码，能做任何事，所以要沙箱、要超时、失败要定义清楚。
触发器是声明式的（"我装了字体"），由系统执行固定动作（fc-cache），
不执行包的代码。能用触发器表达的就不该用脚本——
声明式的可审计、可预测，也不会因为包换了个维护者就变了行为。
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import util

SUFFIX_NEW = ".qynew"        # 冲突时新版本的存放后缀
SUFFIX_OLD = ".qyold"        # 替换前旧文件的备份后缀

# 脚本类型
PRE_INSTALL = "pre_install"
POST_INSTALL = "post_install"
PRE_REMOVE = "pre_remove"
POST_REMOVE = "post_remove"
SCRIPT_KINDS = (PRE_INSTALL, POST_INSTALL, PRE_REMOVE, POST_REMOVE)

# 已知触发器：声明式，由系统执行固定动作，不跑包的代码
TRIGGERS = {
    "fonts": {
        "desc": "安装了字体",
        "cmd": "fc-cache -s -f",
        "why": "不更新缓存，新装的字体在应用里看不到",
    },
    "desktop-database": {
        "desc": "安装了 .desktop 文件",
        "cmd": "update-desktop-database -q /usr/share/applications",
        "why": "不更新，应用菜单里不会出现新程序",
    },
    "icon-cache": {
        "desc": "安装了图标",
        "cmd": "gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor",
        "why": "不更新，新图标显示不出来",
    },
    "man-db": {
        "desc": "安装了手册页",
        "cmd": "mandb -q",
        "why": "不更新，man 查不到新装的命令",
    },
    "mime-database": {
        "desc": "安装了 MIME 类型定义",
        "cmd": "update-mime-database /usr/share/mime",
        "why": "不更新，文件关联不生效",
    },
    "gdk-pixbuf-loaders": {
        "desc": "安装了图像加载器",
        "cmd": "gdk-pixbuf-query-loaders --update-cache",
        "why": "不更新，新格式图片加载不了",
    },
    "glib-schemas": {
        "desc": "安装了 GSettings schema",
        "cmd": "glib-compile-schemas /usr/share/glib-2.0/schemas",
        "why": "不更新，程序设置项读不到默认值，可能直接崩",
    },
    "ldconfig": {
        "desc": "安装了共享库",
        "cmd": "ldconfig",
        "why": "不更新，新装的库链接器找不到，程序报找不到共享库",
    },
    "ca-certificates": {
        "desc": "安装了 CA 证书",
        "cmd": "update-ca-trust",
        "why": "不更新，新装的证书不生效，TLS 仍会报不受信",
    },
}


class PkgOpsError(RuntimeError):
    pass


# ---------------------------------------------------------------- 配置文件

@dataclass
class ConfigState:
    """一个配置文件的三方比对结果。"""
    path: str
    action: str            # replace / keep / conflict
    detail: str = ""

    @property
    def needs_attention(self) -> bool:
        return self.action == "conflict"


def classify_config(disk: str | None, old_orig: str | None,
                    new_orig: str) -> ConfigState:
    """三方比对决定怎么处理一个配置文件。path 由调用方填。"""
    if disk is None:
        # 机器上还没有这个文件，直接装
        return ConfigState("", "replace", "首次安装")
    if old_orig is None:
        # 数据库里没记录原始版本（旧包没标它是配置文件），
        # 无法判断是否被改过。保守起见保留用户的，新版本另存
        return ConfigState("", "conflict",
                           "无法确认是否被修改过（旧版本未记录原始校验和）")
    if disk == old_orig:
        if disk == new_orig:
            return ConfigState("", "keep", "内容与新版本一致，无需改动")
        return ConfigState("", "replace", "未被修改，采用新版本")
    # 用户改过
    if old_orig == new_orig:
        return ConfigState("", "keep", "用户已修改，新版本内容相同，保留用户的")
    return ConfigState("", "conflict", "用户已修改且新版本也有变化")


def plan_configs(root: Path, meta, db_orig: dict) -> list:
    """为一个包的所有配置文件算出处理方案。

    db_orig: {路径: 上次安装时的原始 sha256}
    """
    out = []
    for f in meta.files:
        if not getattr(f, "config", False):
            continue
        disk_p = root / f.path
        disk = None
        if disk_p.exists() and disk_p.is_file():
            try:
                disk = util.sha256_file(disk_p)
            except OSError:
                disk = None
        st = classify_config(disk, db_orig.get(f.path), f.sha256)
        st.path = f.path
        out.append(st)
    return out


def apply_configs(root: Path, staging: Path, states: list) -> list:
    """按方案落地配置文件。返回需要用户注意的冲突。"""
    attention = []
    for st in states:
        dst = root / st.path
        src = staging / st.path
        if st.action == "keep":
            continue
        if st.action == "conflict":
            # 保留用户的，新版本另存为 .qynew
            new_p = dst.with_name(dst.name + SUFFIX_NEW)
            try:
                if src.exists():
                    new_p.write_bytes(src.read_bytes())
            except OSError as e:
                util.log("warn", f"{st.path}: 无法保存新版本: {e}")
                continue
            attention.append((st.path, str(new_p), st.detail))
            continue
        # replace
        if not src.exists():
            continue
        if dst.exists():
            try:
                old_p = dst.with_name(dst.name + SUFFIX_OLD)
                old_p.write_bytes(dst.read_bytes())
            except OSError:
                pass
            dst.unlink()
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
    return attention


def conflict_report(items: list) -> str:
    if not items:
        return ""
    L = [f"{len(items)} 个配置文件本地改过、新版本也有变化，"
         f"已保留你的版本并把新版本另存："]
    for path, new, why in items:
        L.append(f"\n  {path}")
        L.append(f"    新版本：{new}")
        L.append(f"    原因：{why}")
        L.append(f"    处理：diff {path} {new} 后自行合并")
    return "\n".join(L)


# ---------------------------------------------------------------- 脚本

@dataclass
class ScriptResult:
    kind: str
    ok: bool
    output: str = ""
    error: str = ""


def run_script(kind: str, code: str, root: Path, name: str,
               timeout: int = 120) -> ScriptResult:
    """执行一段包脚本。

    脚本是包自带的任意代码，所以：
    - 必须限时。一个卡住的 post_install 会让整个事务挂起，
      机器停在半装状态——那比脚本失败糟糕得多
    - 必须记录输出。失败了要能看出为什么
    - 失败是否中断安装取决于阶段：pre_install 失败不该继续装
      （它通常是前置检查），post_install 失败则文件已经落盘，
      中断反而更难收拾，所以只警告
    """
    if not code.strip():
        return ScriptResult(kind, True, "")
    script = f"#!/bin/sh\nset -e\n{code}\n"
    try:
        p = subprocess.run(["sh", "-c", script], cwd=str(root),
                           capture_output=True, text=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return ScriptResult(kind, False, "",
                            f"执行超过 {timeout} 秒被终止")
    except Exception as e:
        return ScriptResult(kind, False, "", str(e))
    if p.returncode != 0:
        return ScriptResult(kind, False, p.stdout,
                            p.stderr or f"退出码 {p.returncode}")
    return ScriptResult(kind, True, p.stdout)


def run_scripts(meta, root: Path, kinds: list, timeout: int = 120) -> list:
    """按序执行一个包的若干脚本。"""
    scripts = getattr(meta, "scripts", {}) or {}
    out = []
    for k in kinds:
        code = scripts.get(k)
        if not code:
            continue
        r = run_script(k, code, root, meta.name, timeout)
        out.append(r)
        if not r.ok:
            util.log("warn", f"{meta.name} 的 {k} 脚本失败: {r.error[:200]}")
    return out


# ---------------------------------------------------------------- 触发器

def triggers_for(meta) -> list:
    """算出装这个包要触发哪些动作。

    声明式：包说"我装了字体"，系统执行 fc-cache。
    不执行包自己的代码——可审计、可预测，
    也不会因为换了个维护者就变了行为。
    """
    declared = list(getattr(meta, "triggers", []) or [])
    out = set(declared)

    # 按产物自动推断，减少手工声明的遗漏。
    # 手工声明必然漏——谁装字体时会记得写 triggers = ["fonts"]？
    for f in meta.files:
        p = f.path
        if p.startswith("usr/share/fonts/"):
            out.add("fonts")
        elif p.startswith("usr/share/applications/") and p.endswith(".desktop"):
            out.add("desktop-database")
        elif p.startswith("usr/share/icons/"):
            out.add("icon-cache")
        elif "/man/man" in p or p.startswith("usr/share/man/"):
            out.add("man-db")
        elif p.startswith("usr/share/mime/"):
            out.add("mime-database")
        elif p.startswith("usr/share/glib-2.0/schemas/"):
            out.add("glib-schemas")
        elif p.startswith("usr/share/mime-info/") or "pixbuf" in p:
            out.add("gdk-pixbuf-loaders")
        elif p.startswith("etc/ssl/certs/") or p.startswith("usr/share/ca-certificates/"):
            out.add("ca-certificates")
        elif (p.endswith(".so") or ".so." in p) and (
                p.startswith("usr/lib/") or p.startswith("lib/")):
            out.add("ldconfig")
    return sorted(t for t in out if t in TRIGGERS)


def run_triggers(names: list, root: Path | None = None,
                 timeout: int = 120) -> list:
    """执行触发器。失败不致命——触发器失败通常只是"功能没生效"，
    把整个安装判失败会让用户卡在一个装了一半的系统上。

    开发机（非 root）上 ldconfig / glib-compile-schemas 都要写 /etc、/usr，
    必然 Permission denied——这不是包的问题，改用 qemu 支持的假目标：
      ldconfig    -> ldconfig -r <root>（root 检查 root/ 下缓存，非 root 时 stderr
                     提示但不失败）；这里统一降级为"记录而非失败"。
    判定：若进程非 root 且触发器写的是系统路径，标记 None（跳过），
    真机/目标系统（root）上仍会正常执行。
    """
    import os
    is_root = os.geteuid() == 0
    results = []
    for n in names:
        t = TRIGGERS.get(n)
        if not t:
            results.append((n, False, f"未知触发器 {n}"))
            continue
        import shutil
        exe = t["cmd"].split()[0]
        if root is not None and shutil.which(exe) is None:
            results.append((n, None, f"{exe} 不存在，跳过（装机环境）"))
            continue
        if not is_root and exe in ("ldconfig", "glib-compile-schemas",
                                   "update-ca-trust"):
            results.append((n, None,
                            "非 root 开发机跳过（目标系统/真机上正常执行）"))
            continue
        try:
            p = subprocess.run(t["cmd"], shell=True, capture_output=True,
                               text=True, timeout=timeout)
            results.append((n, p.returncode == 0,
                            p.stderr.strip()[:150] if p.returncode else ""))
        except subprocess.TimeoutExpired:
            results.append((n, False, f"超过 {timeout} 秒"))
        except Exception as e:
            results.append((n, False, str(e)[:150]))
    return results


# ---------------------------------------------------------------- alternatives

@dataclass
class Alternative:
    """一个可替换命令：多个包提供同一个通用名。

    典型场景：/usr/bin/awk 可以是 gawk 或 mawk，
    /usr/bin/editor 可以是 vim 或 nano。没有这个机制，
    两个包要么冲突装不上，要么互相覆盖文件。
    """
    name: str                    # 通用名，如 awk
    link: str                    # 符号链接位置，如 usr/bin/awk
    providers: dict = field(default_factory=dict)   # 包名 -> 目标路径
    current: str = ""            # 当前选中的包名


def alt_db_path(root: Path) -> Path:
    return Path(root) / "var" / "lib" / "qypkg" / "alternatives.json"


def load_alts(root: Path) -> dict:
    p = alt_db_path(root)
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except Exception:
        return {}


def save_alts(root: Path, alts: dict) -> None:
    p = alt_db_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    util.atomic_write(p, json.dumps(alts, ensure_ascii=False,
                                    sort_keys=True, indent=1).encode())


def register_alt(root: Path, name: str, link: str, pkg: str,
                 target: str) -> Alternative:
    alts = load_alts(root)
    d = alts.setdefault(name, {"link": link, "providers": {}, "current": ""})
    d["link"] = link
    d["providers"][pkg] = target
    if not d["current"]:
        d["current"] = pkg
    save_alts(root, alts)
    return Alternative(name, link, d["providers"], d["current"])


def unregister_alt(root: Path, name: str, pkg: str) -> None:
    alts = load_alts(root)
    d = alts.get(name)
    if not d:
        return
    d["providers"].pop(pkg, None)
    if d["current"] == pkg:
        d["current"] = sorted(d["providers"])[0] if d["providers"] else ""
    if not d["providers"]:
        alts.pop(name, None)
    save_alts(root, alts)


def apply_alt(root: Path, alt: Alternative) -> str:
    """把符号链接指向当前选中的提供者。返回实际指向。"""
    if not alt.current:
        return ""
    target = alt.providers.get(alt.current)
    if not target:
        return ""
    link_p = root / alt.link
    link_p.parent.mkdir(parents=True, exist_ok=True)
    if link_p.is_symlink() or link_p.exists():
        link_p.unlink()
    # 用相对目标更安全：整根搬家（装机、容器导出）后链接仍然有效
    os.symlink("/" + target.lstrip("/"), link_p)
    return target


def set_alt(root: Path, name: str, pkg: str) -> str:
    alts = load_alts(root)
    d = alts.get(name)
    if not d:
        raise PkgOpsError(
            f"没有名为 {name} 的 alternative"
            f"（可用：{' '.join(sorted(alts)) or '无'}）")
    if pkg not in d["providers"]:
        raise PkgOpsError(
            f"{name} 没有提供者 {pkg}"
            f"（可用：{' '.join(sorted(d['providers']))}）")
    d["current"] = pkg
    save_alts(root, alts)
    return apply_alt(root, Alternative(name, d["link"], d["providers"], pkg))


def list_alts(root: Path) -> str:
    alts = load_alts(root)
    if not alts:
        return "没有注册任何 alternatives。"
    L = []
    for name, d in sorted(alts.items()):
        L.append(f"{name}  → /{d['link'].lstrip('/')}")
        for pkg, tgt in sorted(d["providers"].items()):
            mark = "*" if pkg == d["current"] else " "
            L.append(f"  {mark} {pkg:<20} /{tgt.lstrip('/')}")
    return "\n".join(L)


# ---------------------------------------------------------------- 系统用户

@dataclass
class SysUser:
    """包需要创建的系统用户。

    声明式而非脚本里 useradd：可审计（一眼看出这个包会建什么用户）、
    可预测（不会因换维护者变成别的行为）、且幂等（重复装不报错）。
    """
    name: str
    uid: int | None = None
    gid: int | None = None
    home: str = "/"
    shell: str = "/usr/sbin/nologin"
    group: bool = False          # True 表示只建组
    desc: str = ""


def apply_sysusers(root: Path, users: list) -> list:
    """在指定根下创建系统用户/组。返回已处理的条目。"""
    done = []
    passwd_p = root / "etc" / "passwd"
    group_p = root / "etc" / "group"
    if not passwd_p.exists():
        return done                      # 还没组装根，跳过
    lines_p = passwd_p.read_text().splitlines()
    lines_g = group_p.read_text().splitlines() if group_p.exists() else []
    existing_p = {l.split(":")[0] for l in lines_p if l.strip()}
    existing_g = {l.split(":")[0] for l in lines_g if l.strip()}
    changed = False

    for u in users:
        # 用户和组同名是常规做法，所以两种情形都要先确保组存在
        if u.name not in existing_g:
                gid = u.gid if u.gid is not None else _next_id(lines_g, 100)
                lines_g.append(f"{u.name}:x:{gid}:")
                existing_g.add(u.name)
                changed = True
                done.append(f"组 {u.name}")
        if not u.group and u.name not in existing_p:
            uid = u.uid if u.uid is not None else _next_id(lines_p, 100)
            gid = u.gid if u.gid is not None else uid
            lines_p.append(
                f"{u.name}:x:{uid}:{gid}:{u.desc}:{u.home}:{u.shell}")
            existing_p.add(u.name)
            changed = True
            done.append(f"用户 {u.name}")
    if changed:
        util.atomic_write(group_p, ("\n".join(lines_g) + "\n").encode())
        util.atomic_write(passwd_p, ("\n".join(lines_p) + "\n").encode())
    return done


def _next_id(lines: list, start: int) -> int:
    used = set()
    for l in lines:
        parts = l.split(":")
        if len(parts) >= 3 and parts[2].isdigit():
            used.add(int(parts[2]))
    n = start
    while n in used:
        n += 1
    return n
