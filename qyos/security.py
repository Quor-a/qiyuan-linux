"""漏洞响应与安全公告。

系统发布只是开始，真正考验发行版的是出事之后。这一块决定：
一个 CVE 公布后，多久能知道哪些包受影响、多久能出修复包、
用户多久能拿到。

这里实现：
  * 公告（Advisory）的定义与签发
  * 受影响包查询：按 CVE / 包版本区间 / 已装系统，算出谁需要修
  * 修复优先级判定
  * 重建清单生成：改了一个包，哪些包必须跟着重编
  * 公告索引：供 qypkg 在升级前提示

刻意做对的两件事：
  1. **按版本区间判定，不是按版本号相等**。CVE 影响 1.2~2.0，
     只查 "version == 1.2" 会漏掉绝大多数受影响的安装
  2. **改一个包要算出谁要重编**。共享库一改，所有链接它的包都得重编，
     只发新库不发依赖方，运行时会炸
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from pathlib import Path

from . import util

# 严重级别
CRITICAL = "critical"
HIGH = "high"
MODIUM = "medium"
LOW = "low"
SEVERITIES = (CRITICAL, HIGH, MODIUM, LOW)

SEVERITY_ORDER = {CRITICAL: 0, HIGH: 1, MODIUM: 2, LOW: 3}


class SecurityError(RuntimeError):
    pass


@dataclass
class Affected:
    """一个受影响的版本区间。"""
    package: str
    introduced: str          # 引入缺陷的版本
    fixed: str | None        # 已修复的版本；None = 尚未修复
    affected_ranges: list = field(default_factory=list)  # 额外受影响区间

    def is_affected(self, version: str) -> bool:
        """判断某个版本是否受影响。"""
        try:
            if self.fixed and _vcmp(version, self.fixed) >= 0:
                return False                      # 已修到或超过修复版本
            if _vcmp(version, self.introduced) < 0:
                return False                      # 缺陷还没引入
            return True
        except ValueError:
            # 版本号格式无法比较时，按"可能受影响"处理并留痕
            return True

    def is_fixed(self, version: str) -> bool:
        return self.fixed is not None and _vcmp(version, self.fixed) >= 0


@dataclass
class Advisory:
    """一条安全公告。"""
    id: str                     # QYSA-2026-0001
    title: str
    severity: str
    description: str = ""
    cves: list = field(default_factory=list)
    affected: list = field(default_factory=list)   # [Affected]
    references: list = field(default_factory=list)
    published: int = 0
    updated: int = 0
    fixed_by: list = field(default_factory=list)   # 修复这个公告需要升级到的包

    def __post_init__(self):
        if self.severity not in SEVERITIES:
            raise SecurityError(f"未知的严重级别: {self.severity}")
        if not self.published:
            self.published = int(time.time())

    def to_dict(self) -> dict:
        return {
            "id": self.id, "title": self.title, "severity": self.severity,
            "description": self.description, "cves": self.cves,
            "references": self.references,
            "published": self.published, "updated": self.updated,
            "affected": [{
                "package": a.package, "introduced": a.introduced,
                "fixed": a.fixed, "ranges": a.affected_ranges,
            } for a in self.affected],
            "fixed_by": self.fixed_by,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Advisory":
        return cls(
            id=d["id"], title=d["title"], severity=d["severity"],
            description=d.get("description", ""),
            cves=d.get("cves", []), references=d.get("references", []),
            published=d.get("published", 0), updated=d.get("updated", 0),
            fixed_by=d.get("fixed_by", []),
            affected=[Affected(a["package"], a["introduced"], a.get("fixed"),
                               a.get("ranges", []))
                      for a in d.get("affected", [])],
        )


def _vkey(v: str) -> tuple:
    """把版本号拆成可比较的元组。

    发行版的版本号五花八门（1.2.3 / 1.2.3-4 / 2.0rc1 / 1.2.3+deb1），
    只按点分数字比较会漏，这里尽量兼容常见写法。
    """
    import re
    v = str(v).strip()
    # 去掉发行号后缀（-4）和本地版本（+deb1）
    v = re.split(r"[-+]", v)[0]
    parts = []
    for chunk in re.split(r"[._]", v):
        m = re.match(r"^(\d+)(.*)$", chunk)
        if m:
            parts.append((0, int(m.group(1)), m.group(2)))
        else:
            parts.append((1, 0, chunk))
    return tuple(parts)


def _vcmp(a: str, b: str) -> int:
    ka, kb = _vkey(a), _vkey(b)
    n = max(len(ka), len(kb))
    ka = ka + ((1, 0, ""),) * (n - len(ka))
    kb = kb + ((1, 0, ""),) * (n - len(kb))
    for x, y in zip(ka, kb):
        if x[0] != y[0] or x[1] != y[1]:
            return -1 if (x[0], x[1]) < (y[0], y[1]) else 1
        if x[2] != y[2]:
            # rc < 正式版：1.0rc1 < 1.0
            if x[2] and not y[2]:
                return -1
            if y[2] and not x[2]:
                return 1
            return -1 if x[2] < y[2] else 1
    return 0


# ---------------------------------------------------------------- 索引

class AdvisoryDB:
    """公告库。落盘为一个 JSON，供构建、装机、升级三处共用。"""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.advisories: dict = {}
        self._load()

    def _load(self) -> None:
        if not self.path.exists():
            return
        try:
            data = json.loads(self.path.read_text())
        except (json.JSONDecodeError, OSError):
            return
        for d in data.get("advisories", []):
            a = Advisory.from_dict(d)
            self.advisories[a.id] = a

    def save(self) -> None:
        data = {"generated": int(time.time()),
                "count": len(self.advisories),
                "advisories": [a.to_dict() for a in self.advisories.values()]}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        util.atomic_write(self.path, json.dumps(
            data, ensure_ascii=False, indent=1, sort_keys=True).encode())

    def add(self, adv: Advisory) -> None:
        if adv.id in self.advisories:
            raise SecurityError(f"公告已存在: {adv.id}")
        self.advisories[adv.id] = adv
        self.save()

    def get(self, aid: str) -> Advisory | None:
        return self.advisories.get(aid)

    def by_cve(self, cve: str) -> list:
        cve = cve.upper()
        return [a for a in self.advisories.values()
                if cve in [c.upper() for c in a.cves]]

    def by_package(self, package: str) -> list:
        return [a for a in self.advisories.values()
                if any(x.package == package for x in a.affected)]

    def remove(self, aid: str) -> bool:
        if aid not in self.advisories:
            return False
        del self.advisories[aid]
        self.save()
        return True


# ---------------------------------------------------------------- 查询

def scan_system(root: Path, db: AdvisoryDB) -> dict:
    """扫描一个已装系统，报出存在的漏洞。

    这是用户最需要的功能："我这台机器上有什么没修"。
    """
    from . import pkgmgr as PM
    root = Path(root)
    db_pkgs = PM.DB(root)
    installed = db_pkgs.installed()

    findings = []
    for name, rec in sorted(installed.items()):
        for adv in db.by_package(name):
            for aff in adv.affected:
                if aff.package != name:
                    continue
                if aff.is_affected(rec["version"]):
                    findings.append({
                        "package": name,
                        "version": rec["version"],
                        "advisory": adv.id,
                        "title": adv.title,
                        "severity": adv.severity,
                        "cves": adv.cves,
                        "fixed_in": aff.fixed,
                        "fixable": aff.fixed is not None,
                    })

    findings.sort(key=lambda f: (SEVERITY_ORDER.get(f["severity"], 9),
                                 f["package"]))
    counts = {}
    for f in findings:
        counts[f["severity"]] = counts.get(f["severity"], 0) + 1

    return {"root": str(root), "findings": findings, "counts": counts,
            "total": len(findings),
            "unfixable": sum(1 for f in findings if not f["fixable"])}


def render_scan(result: dict) -> str:
    lines = []
    if not result["findings"]:
        return f"{result['root']}: 未发现已知漏洞"
    lines.append(f"{result['root']}: 发现 {result['total']} 个问题")
    for sev in SEVERITIES:
        n = result["counts"].get(sev, 0)
        if n:
            lines.append(f"  {sev}: {n}")
    lines.append("")
    for f in result["findings"]:
        cve = ",".join(f["cves"]) or "—"
        fix = f["fixed_in"] or "尚无修复版本"
        mark = "可修复" if f["fixable"] else "待上游修复"
        lines.append(f"  [{f['severity']}] {f['package']}-{f['version']} "
                     f"{cve} {f['advisory']} → 修于 {fix}（{mark}）")
    if result["unfixable"]:
        lines.append("")
        lines.append(f"  注意：{result['unfixable']} 个问题上游尚未发布修复，"
                     f"需考虑临时缓解措施")
    return "\n".join(lines)


def rebuild_closure(recipes: dict, changed: list) -> list:
    """改了这些包，哪些包必须重编。

    共享库改了，所有链接它的包都要重编。只发新库不发依赖方，
    轻则符号找不到，重则运行时内存踩踏。
    """
    dependents: dict = {}
    for name, r in recipes.items():
        for d in (r.depends or []) + (r.makedepends or []):
            dependents.setdefault(d, set()).add(name)

    order = []
    seen = set()
    stack = list(changed)
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        if n not in changed:
            order.append(n)
        for dep in dependents.get(n, ()):
            if dep not in seen:
                stack.append(dep)
    return sorted(order)


def priority(adv: Advisory, installed_count: int = 0) -> tuple:
    """修复优先级。返回 (等级, 理由)。"""
    reasons = []
    if adv.severity == CRITICAL:
        reasons.append("严重级别为 critical")
    if any("RCE" in _t or "远程代码执行" in _t for _t in [adv.title, adv.description]):
        reasons.append("涉及远程代码执行")
    if any("privilege" in _t.lower() or "提权" in _t for _t in [adv.title, adv.description]):
        reasons.append("涉及权限提升")
    if installed_count > 100:
        reasons.append(f"影响面广（{installed_count} 个包依赖）")
    if not reasons:
        reasons.append(f"严重级别 {adv.severity}")
    rank = SEVERITY_ORDER.get(adv.severity, 9)
    if any("RCE" in _t or "远程代码执行" in _t for _t in [adv.title, adv.description]):
        rank -= 0.5
    return (rank, "; ".join(reasons))
