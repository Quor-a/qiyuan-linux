"""构建编排器：分层并行调度、产物缓存、失败重试、耗时统计。

串行构建 900 个包是不现实的。配方依赖图天然分层：同一层内没有互相依赖，
可以并行。编排器负责：

  1. 把依赖图按层切开（Kahn 分层）
  2. 每层内并行构建（多进程，互不干扰）
  3. 包级产物缓存：配方内容 + 依赖版本没变就跳过
  4. 失败重试，失败不影响同层其他包
  5. 记录每个包的耗时，找出拖慢全量构建的瓶颈

缓存键 = sha256(配方文件) + 所有构建依赖的版本 → 任一变化才真正重编。
这是"全量构建从 3 小时降到几分钟"的关键。
"""
from __future__ import annotations

import concurrent.futures as cf
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from . import util
from . import recipe as recipemod
from .deps import Universe


class Orchestrator:
    def __init__(self, root: Path, jobs: int | None = None,
                 cache_file: str = "var/cache/build-cache.json"):
        self.root = Path(root)
        self.jobs = jobs or max(1, os.cpu_count() or 1)
        self.recipes = recipemod.load_tree(self.root / "recipes")
        self.cache_path = self.root / cache_file
        self.cache = self._load_cache()
        self.stats: dict = {}

    # -- 缓存 --------------------------------------------------------

    def _load_cache(self) -> dict:
        if self.cache_path.exists():
            try:
                return json.loads(self.cache_path.read_text())
            except Exception:
                util.log("warn", "构建缓存损坏，忽略")
        return {}

    def _save_cache(self) -> None:
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        util.atomic_write(self.cache_path,
                          json.dumps(self.cache, ensure_ascii=False, indent=1,
                                     sort_keys=True).encode())

    def cache_key(self, name: str) -> str:
        """配方内容 + 源码内容 + 依赖版本 = 缓存键。

        源码内容必须进缓存键。只算配方文件哈希的话，改了 C 源码但没改
        版本号时缓存会命中，编出来的是旧代码打的新版本号的包——
        这种包能装上、能跑，只是行为是旧的，最难排查。
        """
        r = self.recipes[name]
        parts = [util.sha256_file(r.path), r.version, str(r.release)]
        parts.append(self._source_digest(r))
        for d in sorted(r.makedepends + r.depends):
            dep = self.recipes.get(d)
            if dep:
                parts.append(f"{dep.name}-{dep.version}-{dep.release}")
        return util.sha256_bytes("|".join(parts).encode())[:32]

    def _source_digest(self, r) -> str:
        """算出源码内容的指纹。本地目录就遍历文件，远程源码用 URL+校验和。"""
        import hashlib
        h = hashlib.sha256()
        root = self.root
        for s in (r.source or []):
            if s.startswith(("http://", "https://", "ftp://")):
                # 远程源码靠配方里锁定的 sha256 就够了
                h.update(s.encode())
                if r.sha256:
                    h.update("".join(r.sha256).encode())
                continue
            p = root / s
            if not p.exists():
                h.update(f"(missing){s}".encode())
                continue
            if p.is_file():
                h.update(util.sha256_bytes(p.read_bytes()).encode())
                continue
            files = sorted(x for x in p.rglob("*") if x.is_file())
            for f in files:
                rel = str(f.relative_to(p))
                h.update(rel.encode())
                try:
                    h.update(util.sha256_file(f).encode())
                except OSError:
                    h.update(b"(unreadable)")
        return h.hexdigest()[:32]

    def is_cached(self, name: str) -> bool:
        return self.cache.get(name) == self.cache_key(name)

    def mark_cached(self, name: str) -> None:
        self.cache[name] = self.cache_key(name)

    # -- 分层 --------------------------------------------------------

    def _universe(self) -> "Universe":
        """构造带循环打破计划的包世界。

        直接 new Universe() 会在遇到 freetype↔harfbuzz 这类真实存在的环时
        抛 DepError——包库小的时候没有环所以没暴露，
        扩到 177 个包之后 qybuild --orchestrate 直接崩掉。
        """
        from . import cycles as CY
        cp = CY.plan(self.recipes)
        u = Universe(broken=cp.broken_deps)
        for r in self.recipes.values():
            u.add(r)
        return u

    def layers(self, names: list) -> list:
        """按依赖深度分层，同层可并行。"""
        u = self._universe()

        order = u.resolve(names)
        depth: dict = {}
        for n in order:
            deps = [d for d in self.recipes[n].makedepends
                    + self.recipes[n].depends if d in self.recipes]
            depth[n] = max((depth.get(d, -1) + 1 for d in deps), default=0)
        out: list = []
        for n in sorted(order, key=lambda x: (depth[x], x)):
            while len(out) <= depth[n]:
                out.append([])
            out[depth[n]].append(n)
        return out

    # -- 构建 --------------------------------------------------------

    def _build_one(self, name: str, extra_args: list) -> tuple:
        """在子进程里构建一个包，失败可重试。返回 (name, ok, 耗时秒, 说明)。"""
        cmd = [sys.executable, str(self.root / "bin" / "qybuild"), name,
               "--root", str(self.root), *extra_args]
        t0 = time.time()
        p = subprocess.run(cmd, capture_output=True, text=True,
                           cwd=str(self.root))
        dt = time.time() - t0
        if p.returncode == 0:
            return name, True, dt, ""
        tail = "\n".join((p.stdout + p.stderr).strip().splitlines()[-8:])
        return name, False, dt, tail

    def build(self, names: list | None = None, force: bool = False,
              retries: int = 1, extra_args: list | None = None) -> dict:
        names = names or list(self.recipes)
        extra_args = extra_args or []
        if force:
            extra_args = list(extra_args) + ["--force"]

        lay = self.layers(names)
        total = sum(len(l) for l in lay)
        util.log("ok", f"编排 {total} 个包 / {len(lay)} 层 / {self.jobs} 并行")
        for i, l in enumerate(lay):
            util.log("info", f"  第 {i} 层: {' '.join(l)}")

        t_start = time.time()
        done, failed, skipped = [], [], []
        for i, layer in enumerate(lay):
            todo = []
            for n in layer:
                if not force and self.is_cached(n):
                    skipped.append(n)
                    util.log("info", f"{n} 命中产物缓存，跳过")
                else:
                    todo.append(n)
            if not todo:
                continue
            util.log("step", f"第 {i} 层开始（{len(todo)} 个包）")
            results = {}
            with cf.ThreadPoolExecutor(max_workers=self.jobs) as pool:
                futs = {pool.submit(self._build_one, n, extra_args): n
                        for n in todo}
                for fut in cf.as_completed(futs):
                    name, ok, dt, msg = fut.result()
                    results[name] = (ok, dt, msg)

            for n in todo:
                ok, dt, msg = results[n]
                self.stats[n] = dt
                if ok:
                    self.mark_cached(n)
                    done.append(n)
                    util.log("ok", f"{n} 完成 ({util.fmt_duration(dt)})")
                else:
                    # 失败重试一次，很多时候是并行资源竞争导致的
                    for attempt in range(retries):
                        util.log("warn", f"{n} 失败，重试 {attempt + 1}/{retries}")
                        _, ok, dt, msg = self._build_one(n, extra_args)
                        if ok:
                            break
                    if ok:
                        self.mark_cached(n)
                        done.append(n)
                        util.log("ok", f"{n} 重试后完成")
                    else:
                        failed.append(n)
                        util.log("err", f"{n} 构建失败:\n{msg}")
            self._save_cache()

        self._save_cache()
        elapsed = time.time() - t_start
        summary = {"done": done, "failed": failed, "skipped": skipped,
                   "elapsed": elapsed, "stats": self.stats}
        util.log("ok", f"编排完成：成功 {len(done)}，失败 {len(failed)}，"
                       f"缓存跳过 {len(skipped)}，耗时 {util.fmt_duration(elapsed)}")
        if failed:
            util.log("err", "失败的包: " + ", ".join(failed))
        return summary

    # -- 报告 --------------------------------------------------------

    def slowest(self, n: int = 10) -> list:
        return sorted(self.stats.items(), key=lambda kv: -kv[1])[:n]

    def write_report(self, path: Path, summary: dict) -> None:
        lines = ["# 构建耗时报告", ""]
        lines.append(f"总耗时 {util.fmt_duration(summary['elapsed'])} · "
                     f"成功 {len(summary['done'])} · "
                     f"失败 {len(summary['failed'])} · "
                     f"缓存命中 {len(summary['skipped'])}")
        lines += ["", "## 耗时最长的包", "", "| 包 | 耗时 |", "|---|---|"]
        for name, dt in self.slowest(20):
            lines.append(f"| {name} | {util.fmt_duration(dt)} |")
        lines += ["", "## 全部耗时", "", "| 包 | 耗时 |", "|---|---|"]
        for name, dt in sorted(self.stats.items(), key=lambda kv: -kv[1]):
            lines.append(f"| {name} | {util.fmt_duration(dt)} |")
        util.atomic_write(Path(path), "\n".join(lines).encode())
        util.log("ok", f"耗时报告已写入 {path}")
