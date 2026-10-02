"""依赖求解。

支持：版本约束（>=、<、=）、虚拟包与提供者、冲突检测、循环依赖检测、
拓扑排序，以及"为什么需要这个包"的反查。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field


class DepError(RuntimeError):
    pass


OPS = (">=", "<=", "==", "!=", ">", "<", "=")
_DEP_RE = re.compile(r"^\s*([A-Za-z0-9._+\-]+)\s*(.*)$")


@dataclass
class Dep:
    raw: str
    name: str
    op: str = ""
    ver: str = ""

    def satisfied_by(self, name: str, evr: str) -> bool:
        if name != self.name:
            return False
        if not self.op:
            return True
        return version_cmp(evr.split("-")[0], self.op, self.ver)

    def __str__(self) -> str:
        return self.raw


def parse_dep(s: str) -> Dep:
    m = _DEP_RE.match(s)
    if not m:
        if s.startswith("/"):
            raise DepError(
                f"无法解析依赖: {s}\n"
                f"  依赖与 provides 只支持包名或虚拟包名，不支持文件路径。\n"
                f"  要表达『提供 /bin/sh』请写 provides = [\"sh\"]，"
                f"文件位置由 usr 合并布局保证")
        raise DepError(f"无法解析依赖: {s}")
    name, rest = m.group(1), (m.group(2) or "").strip()
    if not rest:
        return Dep(raw=s, name=name)
    for op in OPS:
        if rest.startswith(op):
            return Dep(raw=s, name=name, op="==" if op == "=" else op,
                       ver=rest[len(op):].strip())
    raise DepError(f"无法解析依赖: {s}")


def _split_ver(v: str) -> list:
    parts = []
    for seg in re.split(r"[._\-+]", v):
        parts.append(int(seg) if seg.isdigit() else seg)
    return parts


def version_cmp(a: str, op: str, b: str) -> bool:
    """简化版版本比较：逐段数值优先，字母段按字符串。"""
    pa, pb = _split_ver(a), _split_ver(b)
    n = max(len(pa), len(pb))
    pa += [0] * (n - len(pa))
    pb += [0] * (n - len(pb))
    r = 0
    for x, y in zip(pa, pb):
        if x == y:
            continue
        if isinstance(x, int) and isinstance(y, int):
            r = -1 if x < y else 1
        else:
            r = -1 if str(x) < str(y) else 1
        break
    return {">=": r >= 0, "<=": r <= 0, "==": r == 0, "!=": r != 0,
            ">": r > 0, "<": r < 0}.get(op, False)


class Universe:
    """包世界：所有已知包的提供者与元数据。"""

    def __init__(self, broken: dict | None = None):
        self.pkgs: dict = {}        # name -> obj (有 .name/.version/.provides/.depends)
        self.providers: dict = {}   # 能力名 -> [包名]
        # 首轮暂时忽略的依赖 {包名: [依赖]}，用于打破循环依赖。
        # 不这样做的话，遇到 freetype↔harfbuzz 这类真实存在的环，
        # 整个包库一个包都编不了。
        self.broken: dict = broken or {}

    def add(self, pkg) -> None:
        self.pkgs[pkg.name] = pkg
        for cap in ([pkg.name] + list(getattr(pkg, "provides", []) or [])):
            cap_name = parse_dep(cap).name
            self.providers.setdefault(cap_name, [])
            if pkg.name not in self.providers[cap_name]:
                self.providers[cap_name].append(pkg.name)

    @classmethod
    def parse(cls, s: str) -> "Dep":
        return parse_dep(s)

    def provider_of(self, dep: Dep):
        """找出能满足 dep 的包。

        注意 providers 里既有"包自己的名字"也有"它 provides 出来的能力名"。
        从能力名反查到某个包时，说明该包已声明提供此能力，不能再拿
        dep.name 去比对 p.name——两者本来就不相等（libqydemo.so.1 vs
        libqydemo），比对必然失败，所有 provides 反查都会落空。
        只有带版本约束时才需要校验版本。
        """
        names = self.providers.get(dep.name, [])
        for n in names:
            p = self.pkgs.get(n)
            if not p:
                continue
            if not dep.op:
                return p                      # 无版本约束：声明了就满足
            evr = f"{p.version}-{getattr(p, 'release', 1)}"
            if dep.name == p.name:
                if dep.satisfied_by(p.name, evr):
                    return p
            elif version_cmp(evr.split("-")[0], dep.op, dep.ver):
                return p                      # 虚拟提供：按提供者的版本比
        return None

    def provider_of_name(self, name: str):
        """按名字查提供者（供 shlibdeps 反查 soname 用）。"""
        try:
            dep = parse_dep(name)
        except DepError:
            return None
        p = self.provider_of(dep)
        return p.name if p is not None else None

    def resolve(self, targets: list, installed: dict | None = None) -> list:
        """解析依赖闭包，返回拓扑排序后的包名列表。installed 里的包视为已满足。"""
        installed = installed or {}
        order: list = []
        visiting: set = set()
        done: set = set()

        def visit(name: str, stack: list):
            if name in done:
                return
            if name in visiting:
                raise DepError("循环依赖: " + " -> ".join(stack + [name]))
            dep = parse_dep(name)
            p = self.pkgs.get(dep.name)
            if p is None:
                prov = self.provider_of(dep)
                if prov is not None and dep.name not in installed:
                    # 名字是虚拟包名（ssh-server、gui-base…）：必须换成真正的
                    # 提供者继续展开。原来这里只是 pass 掉就返回了，
                    # 于是"装 ssh-server"什么都不会装——形态里大量使用
                    # 虚拟包名，这个 bug 会让整个形态的包集静默缩水。
                    visit(prov.name, stack)
                    return
                if dep.name in installed or self.provider_of(dep):
                    return
                raise DepError(
                    f"缺少包: {dep.name}（被 {' '.join(stack) or '目标'} 需要）")
            visiting.add(name)
            skip = set(self.broken.get(name, ()))
            for d in (getattr(p, "depends", []) or [] if p else []):
                dparsed = parse_dep(d)
                if dparsed.name in installed or d in skip:
                    continue
                prov = self.provider_of(dparsed)
                visit(prov.name if prov else dparsed.name, stack + [name])
            visiting.discard(name)
            done.add(name)
            if p is not None and p.name not in order:
                order.append(p.name)

        for t in targets:
            visit(parse_dep(t).name, [])
        return order

    def why(self, target: str, installed: dict | None = None) -> list:
        """反查哪些包依赖 target（用于判断能否安全卸载）。"""
        out = []
        for name, p in self.pkgs.items():
            for d in (getattr(p, "depends", []) or []):
                if parse_dep(d).name == target:
                    out.append(name)
        return sorted(set(out))


@dataclass
class Conflict:
    a: str
    b: str
    reason: str
