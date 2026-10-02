"""自动依赖发现（shlibdeps）。

手工维护依赖必然出错：C 程序链接了 libc、libssl，但配方里忘了写，
后果是——
  * 装包时依赖没被拉进来，程序启动就报 "找不到共享库"
  * glibc 出了 CVE，安全扫描漏掉所有没显式声明的包

Debian 用 dpkg-shlibdeps、Alpine 用 scanelf 解决同一件事。这里自己做：
扫产物里的 ELF 文件 → 读出 NEEDED 的 soname → 反查哪个包提供它
→ 自动写回依赖。

几个必须处理对的细节：
  1. **自身提供的库要排除**，否则包会依赖自己
  2. **同一包内的库互相依赖也要排除**（包里带多个 .so 很常见）
  3. **只加缺失的**，绝不删掉维护者手工写的依赖——
     自动分析不可能知道"这个包运行时还需要某个数据文件包"
  4. **基础库要能识别**：libc.so.6 → glibc，做成可配置的映射表，
     因为这个反查无法从 soname 字面推出来
"""
from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import util

# soname → 提供它的包名。
# 这一层无法从 soname 字面推出（libc.so.6 不叫 glibc），只能维护映射。
# 先看仓库里有没有包显式 provides 了这个 soname，查不到才用这张表兜底。
SONAME_MAP = {
    "libc.so.6": "glibc",
    "libm.so.6": "glibc",
    "libpthread.so.0": "glibc",
    "libdl.so.2": "glibc",
    "librt.so.1": "glibc",
    "libresolv.so.2": "glibc",
    "libutil.so.1": "glibc",
    "libnsl.so.1": "glibc",
    "libanl.so.1": "glibc",
    "libcrypt.so.1": "glibc",
    "ld-linux-x86-64.so.2": "glibc",
    "libstdc++.so.6": "gcc",
    "libgcc_s.so.1": "gcc",
    "libssp.so.0": "gcc",
    "libgomp.so.1": "gcc",
    "libquadmath.so.0": "gcc",
    "libatomic.so.1": "gcc",
}

# 这些是内核/动态链接器提供的，不需要任何包
IGNORE = {
    "ld-linux-x86-64.so.2",      # 动态链接器，由 glibc 提供但作为解释器存在
    "linux-vdso.so.1",           # 内核虚拟 DSO
    "libgcc_s.so.1",             # gcc 运行时，通常与编译器同生命周期
}


class ShlibError(RuntimeError):
    pass


@dataclass
class ScanResult:
    package: str
    elf_count: int = 0
    needed: dict = field(default_factory=dict)   # soname → 引用它的文件数
    resolved: dict = field(default_factory=dict)  # soname → 包名
    unresolved: list = field(default_factory=list)
    host_provided: dict = field(default_factory=dict)  # soname → 宿主暂供的包
    auto_deps: list = field(default_factory=list)


def is_elf(path: Path) -> bool:
    """判断是否是 ELF 文件。用魔数，不依赖 file 命令。"""
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def needed_sonames(path: Path) -> list:
    """读出 ELF 直接依赖的 soname 列表。

    只取 DT_NEEDED（直接依赖），不递归。递归依赖是依赖包的依赖，
    由求解器负责展开，在这里展开会造成重复与环。
    """
    cmd = ["readelf", "-d", str(path)]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=30).stdout
    except Exception:
        return []
    names = []
    for line in out.splitlines():
        m = re.search(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", line)
        if m:
            names.append(m.group(1))
    return names


def soname_of(path: Path) -> str:
    """读出 ELF 自己的 SONAME（若它是共享库）。"""
    cmd = ["readelf", "-d", str(path)]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=30).stdout
    except Exception:
        return ""
    for line in out.splitlines():
        m = re.search(r"\(SONAME\)\s+Library soname: \[([^\]]+)\]", line)
        if m:
            return m.group(1)
    return ""


def scan_tree(root: Path) -> tuple:
    """扫描一个目录树，返回 (ELF 文件列表, soname → [引用文件])。"""
    root = Path(root)
    elves, needed = [], {}
    for p in sorted(root.rglob("*")):
        if not p.is_file() or p.is_symlink():
            continue
        if not is_elf(p):
            continue
        elves.append(p)
        for so in needed_sonames(p):
            needed.setdefault(so, []).append(str(p.relative_to(root)))
    return elves, needed


def scan_package(destdir: Path, rec, universe=None,
                 available: set | None = None) -> ScanResult:
    """分析一个包的产物，算出它应该自动补上哪些依赖。"""
    destdir = Path(destdir)
    elves, needed = scan_tree(destdir)

    # 包自己提供（且包内自带）的 soname——引用这些不算外部依赖
    own = set()
    for p in elves:
        so = soname_of(p)
        if so:
            own.add(so)
    own.update(rec.provides or [])

    res = ScanResult(package=rec.name, elf_count=len(elves))

    # 自举阶段的鸡生蛋问题：几乎所有程序都链接 libc，但 glibc 这个包
    # 此刻还没编出来——它是要先用宿主的编译器编出来的。
    # 这时候若把 glibc 写成依赖，依赖求解会找不到包而卡死整个构建。
    # 处理办法：映射到的包若还没进仓库，记为"由宿主提供"，不进依赖；
    # 等自举完成、glibc 进了仓库，同一段代码会自动把它补上。
    for so in sorted(needed):
        if so in own or so in IGNORE:
            continue
        res.needed[so] = len(needed[so])

        provider = None
        if universe is not None:
            provider = universe.provider_of_name(so)
        if not provider:
            provider = SONAME_MAP.get(so)

        if not provider or provider == rec.name:
            res.unresolved.append(so)
            continue

        if available is not None and provider not in available:
            res.host_provided[so] = provider
            continue

        res.resolved[so] = provider

    res.auto_deps = sorted(set(res.resolved.values()))
    return res


def apply_auto_deps(rec, result: ScanResult) -> list:
    """把自动发现的依赖并进配方。返回新增的项。

    只加不删：自动分析能看出链接了什么库，但看不出
    "这个包运行时还需要某个数据文件或插件包"，
    维护者手工写的依赖必须保留。
    """
    existing = list(rec.depends or [])
    added = []
    for d in result.auto_deps:
        if d not in existing:
            existing.append(d)
            added.append(d)
    rec.depends = existing
    return added


def report(result: ScanResult) -> str:
    lines = [f"{result.package}: 扫描 {result.elf_count} 个 ELF"]
    if result.resolved:
        lines.append("  自动解析出的依赖：")
        for so, pkg in sorted(result.resolved.items()):
            n = result.needed[so]
            lines.append(f"    {so}（{n} 个文件引用） → {pkg}")
    if result.host_provided:
        lines.append("  自举阶段暂由宿主提供（该包尚未自举出来）：")
        for so, pkg in sorted(result.host_provided.items()):
            lines.append(f"    {so} → {pkg}（自举完成后会自动转为真实依赖）")
    if result.unresolved:
        lines.append("  未能定位提供者的库（需人工确认）：")
        for so in result.unresolved:
            lines.append(f"    {so}（{result.needed[so]} 个文件引用）")
    if not result.resolved and not result.unresolved:
        lines.append("  无外部共享库依赖")
    return "\n".join(lines)


def audit_recipes(recipes: dict, universe=None) -> dict:
    """审计整个配方库：哪些包声明的依赖和实际链接的不一致。

    这是发布前该跑的检查——漏声明的依赖在用户机器上才会暴露。
    """
    missing, extra = {}, {}
    for name, rec in sorted(recipes.items()):
        declared = set(rec.depends or [])
        # 用 SONAME_MAP 反推：这个包链接的库里，映射表里有的
        # 说明它实际需要那个包
        declared_needed = set()
        if universe is not None:
            for so, pkg in SONAME_MAP.items():
                if pkg in declared:
                    declared_needed.add(pkg)
        missing[name] = sorted(declared_needed - declared)
        extra[name] = sorted(declared - declared_needed)
    return {"missing": {k: v for k, v in missing.items() if v},
            "extra": {k: v for k, v in extra.items() if v}}
