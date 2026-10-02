"""发布工程。

从"能跑的构建产物"到"可以发给别人的版本"，中间还有很多事：
版本号怎么定、改了什么要写清楚、镜像和清单要一起发、
用户要能验证自己下载的东西没被换过。

这里实现：
  * 版本号规则与递增（遵循语义化版本）
  * 变更日志：从提交历史和包变更自动生成骨架
  * 发布清单（manifest）：列出所有产物及其校验和
  * 发布完整性校验：用户下载后能自己验一遍

刻意做对的一件事：**发布清单里必须有每个产物的 sha256，
并且清单自己也要签名**。只发镜像不发校验和，用户无法判断
自己拿到的是不是被中间人换过的东西。
"""
from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field
from pathlib import Path

from . import util

SCHEMA = "qiyuan-release/1"


class ReleaseError(RuntimeError):
    pass


# 版本阶段
ALPHA = "alpha"
BETA = "beta"
RC = "rc"
STABLE = "stable"
STAGES = (ALPHA, BETA, RC, STABLE)


@dataclass
class Version:
    major: int = 0
    minor: int = 1
    patch: int = 0
    stage: str = ALPHA
    stage_num: int = 1

    def __str__(self) -> str:
        if self.stage == STABLE:
            return f"{self.major}.{self.minor}.{self.patch}"
        return f"{self.major}.{self.minor}.{self.patch}-{self.stage}.{self.stage_num}"

    @classmethod
    def parse(cls, s: str) -> "Version":
        m = re.match(
            r"^(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?$", s.strip())
        if not m:
            raise ReleaseError(
                f"版本号格式不对: {s}（应为 0.1.0 / 0.1.0-beta.2 / 1.0.0）")
        return cls(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                   m.group(4) or STABLE, int(m.group(5) or 0))

    def key(self) -> tuple:
        # 稳定性排序：alpha < beta < rc < stable
        rank = {ALPHA: 0, BETA: 1, RC: 2, STABLE: 3}
        return (self.major, self.minor, self.patch,
                rank.get(self.stage, 0), self.stage_num)

    def next(self, bump: str = "patch", stage: str | None = None) -> "Version":
        """生成下一个版本号。"""
        v = Version(self.major, self.minor, self.patch,
                    stage or self.stage, self.stage_num)
        if bump == "major":
            v.major += 1; v.minor = 0; v.patch = 0; v.stage_num = 1
        elif bump == "minor":
            v.minor += 1; v.patch = 0; v.stage_num = 1
        elif bump == "patch":
            v.patch += 1; v.stage_num = 1
        elif bump == "stage":
            # 同版本推进阶段：alpha.1 → alpha.2
            v.stage_num += 1
        elif bump == "promote":
            # 推进到下一阶段：alpha → beta → rc → stable
            order = [ALPHA, BETA, RC, STABLE]
            i = order.index(self.stage)
            if i + 1 < len(order):
                v.stage = order[i + 1]
                v.stage_num = 1
            else:
                v.stage = STABLE
                v.stage_num = 0
        else:
            raise ReleaseError(f"未知的递增方式: {bump}")
        return v


@dataclass
class Release:
    version: str
    stage: str = ALPHA
    date: int = 0
    artifacts: list = field(default_factory=list)   # [{path,size,sha256,type}]
    packages: dict = field(default_factory=dict)    # {包名: 版本}
    profiles: list = field(default_factory=list)
    notes: str = ""
    kernel: str = ""
    schema: str = SCHEMA

    def __post_init__(self):
        if not self.date:
            self.date = int(time.time())

    def to_dict(self) -> dict:
        return {"schema": self.schema, "version": self.version,
                "stage": self.stage, "date": self.date,
                "artifacts": self.artifacts, "packages": self.packages,
                "profiles": self.profiles, "notes": self.notes,
                "kernel": self.kernel}

    @classmethod
    def from_dict(cls, d: dict) -> "Release":
        return cls(**{k: v for k, v in d.items() if k in cls.__dataclass_fields__})


def scan_artifacts(root: Path, patterns: list | None = None) -> list:
    """扫描产物目录，算出每个文件的校验和。"""
    patterns = patterns or ["*.img", "*.iso", "*.qyp", "*.tar.*"]
    out = []
    for pat in patterns:
        for p in sorted(Path(root).rglob(pat)):
            if not p.is_file():
                continue
            out.append({
                "path": str(p),
                "name": p.name,
                "size": p.stat().st_size,
                "sha256": util.sha256_file(p),
                "type": _artifact_type(p),
            })
    return out


def _artifact_type(p: Path) -> str:
    n = p.name.lower()
    if n.endswith(".img"):
        return "disk-image"
    if n.endswith(".iso"):
        return "install-media"
    if n.endswith(".qyp"):
        return "package"
    return "archive"


def build_release(root: Path, version: str, stage: str = ALPHA,
                  kernel: str = "", notes: str = "",
                  profiles: list | None = None,
                  patterns: list | None = None) -> Release:
    """构建一个发布对象（含所有产物校验和）。"""
    arts = scan_artifacts(Path(root), patterns)
    pkgs = {}
    try:
        from . import pkgmgr as PM
        db = PM.DB(Path(root))
        pkgs = {n: r["version"] for n, r in db.installed().items()}
    except Exception:
        pass
    return Release(version=version, stage=stage, artifacts=arts,
                   packages=pkgs, profiles=profiles or [],
                   notes=notes, kernel=kernel)


def write_manifest(rel: Release, out_path: Path,
                   sign_key: Path | None = None) -> Path:
    """写出发布清单，可选签名。"""
    from . import format as fmt
    payload = json.dumps(rel.to_dict(), ensure_ascii=False,
                         sort_keys=True, separators=(",", ":")).encode()
    out_path = Path(out_path)
    util.atomic_write(out_path, payload)
    if sign_key and Path(sign_key).exists():
        sig = fmt.sign_digest(bytes.fromhex(util.sha256_bytes(payload)),
                              Path(sign_key))
        util.atomic_write(out_path.with_suffix(out_path.suffix + ".sig"),
                          json.dumps(sig, sort_keys=True).encode())
        util.log("ok", f"发布清单已签名 (keyid={sig['keyid']})")
    else:
        util.log("warn", "发布清单未签名")
    return out_path


def verify_manifest(manifest: Path, pubkey: Path | None = None,
                    check_files: bool = True) -> dict:
    """校验一个发布：清单签名 + 每个产物是否对得上。

    用户下载完第一件事就该跑这个。
    """
    from . import format as fmt
    manifest = Path(manifest)
    payload = manifest.read_bytes()
    problems, checked = [], 0

    sig_path = manifest.with_suffix(manifest.suffix + ".sig")
    sig_ok = None
    if sig_path.exists() and pubkey:
        sig = json.loads(sig_path.read_bytes())
        sig_ok = fmt.verify_digest(
            bytes.fromhex(util.sha256_bytes(payload)), sig, Path(pubkey))
        if not sig_ok:
            problems.append("清单签名校验失败——发布内容可能被替换")
    elif pubkey:
        problems.append("清单没有签名，无法确认来源")

    rel = Release.from_dict(json.loads(payload))

    if check_files:
        for art in rel.artifacts:
            p = Path(art["path"])
            if not p.exists():
                problems.append(f"产物缺失: {art['name']}")
                continue
            if p.stat().st_size != art["size"]:
                problems.append(f"{art['name']} 大小不符")
                continue
            if util.sha256_file(p) != art["sha256"]:
                problems.append(f"{art['name']} 校验和不符——文件已损坏或被替换")
                continue
            checked += 1

    return {"version": rel.version, "signed": sig_ok,
            "artifacts": len(rel.artifacts), "checked": checked,
            "problems": problems, "ok": not problems}


def changelog_since(root: Path, since_tag: str | None = None) -> list:
    """从 git 历史生成变更日志条目。没有 git 就返回空。"""
    import subprocess
    try:
        cmd = ["git", "-C", str(root), "log", "--no-merges",
               "--pretty=format:%h|%s"]
        if since_tag:
            cmd.append(f"{since_tag}..HEAD")
        out = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=30).stdout
    except Exception:
        return []
    entries = []
    for line in out.splitlines():
        if "|" not in line:
            continue
        h, subject = line.split("|", 1)
        entries.append({"hash": h, "subject": subject,
                        "category": _categorize(subject)})
    return entries


def _categorize(subject: str) -> str:
    s = subject.lower()
    if s.startswith(("fix", "修复", "修")):
        return "修复"
    if s.startswith(("feat", "新增", "add")):
        return "新增"
    if s.startswith(("sec", "安全", "cve")):
        return "安全"
    if s.startswith(("perf", "性能")):
        return "性能"
    if s.startswith(("doc", "文档")):
        return "文档"
    return "其他"


def render_changelog(entries: list, version: str) -> str:
    groups: dict = {}
    for e in entries:
        groups.setdefault(e["category"], []).append(e)
    order = ["安全", "修复", "新增", "性能", "文档", "其他"]
    lines = [f"# {version}", ""]
    for cat in order:
        items = groups.get(cat)
        if not items:
            continue
        lines.append(f"## {cat}")
        for e in items:
            lines.append(f"- {e['subject']} (`{e['hash']}`)")
        lines.append("")
    if not entries:
        lines.append("（无变更记录）")
    return "\n".join(lines)
