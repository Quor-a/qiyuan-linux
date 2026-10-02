"""并行下载与包缓存。

升级几十个包时串行下载很慢。这里做三件事：
  * 并发下载到缓存目录，边下边校验 sha256
  * 缓存按 sha256 命中，同一文件不重复下载
  * 失败自动重试，单个失败不影响其他任务

缓存布局：cache/<sha256 前2位>/<完整 sha256>/<文件名>
这样同名不同内容的文件不会互相覆盖，也天然去重。
"""
from __future__ import annotations

import concurrent.futures as cf
import os
import shutil
import urllib.request
from pathlib import Path

from . import util


class DownloadError(RuntimeError):
    pass


def cache_path(cache_dir: Path, sha: str, name: str) -> Path:
    return Path(cache_dir) / sha[:2] / sha / name


GITHUB_MIRRORS = [
    "https://ghproxy.net/{}",          # GitHub 直连不稳时的加速前缀
]


def _mirror_candidates(url: str) -> list[str]:
    """直连失败时依次尝试的镜像候选（仅 GitHub 域名）。"""
    if "github.com" not in url:
        return [url]
    out = [url]
    for m in GITHUB_MIRRORS:
        out.append(m.format(url))
    return out


def _fetch_one(url: str, dest: Path, expected: str | None, timeout: int) -> Path:
    tmp = dest.with_suffix(dest.suffix + ".part")
    tmp.parent.mkdir(parents=True, exist_ok=True)
    last_err: Exception | None = None
    for u in _mirror_candidates(url):
        req = urllib.request.Request(u, headers={"User-Agent": "qiyuan-fetch/0.2"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f)
            # 镜像可能返回 HTML 错误页而非源码包：gzip/xz/tar 魔数以外的开头直接视为失败
            with open(tmp, "rb") as f:
                head = f.read(2)
            if head[:1] == b"<":
                raise DownloadError(f"镜像返回 HTML 错误页: {u}")
            if expected and util.sha256_file(tmp) != expected:
                tmp.unlink(missing_ok=True)
                raise DownloadError(f"校验和不符: {u}")
            os.replace(tmp, dest)
            return dest
        except Exception as e:
            last_err = e
            tmp.unlink(missing_ok=True)
    raise last_err if last_err else DownloadError(f"下载失败: {url}")


class Fetcher:
    def __init__(self, cache_dir: Path, workers: int = 4, timeout: int = 120,
                 retries: int = 2):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.workers = workers
        self.timeout = timeout
        self.retries = retries

    def get(self, url: str, expected: str | None = None) -> Path:
        """串行取一个文件（命中缓存直接返回）。"""
        name = url.rsplit("/", 1)[-1] or "file"
        if expected:
            p = cache_path(self.cache_dir, expected, name)
            if p.exists() and util.sha256_file(p) == expected:
                return p
        else:
            p = self.cache_dir / "unverified" / name
            if p.exists():
                return p
        last = None
        for i in range(self.retries + 1):
            try:
                return _fetch_one(url, p, expected, self.timeout)
            except Exception as e:
                last = e
                if i < self.retries:
                    util.log("warn", f"下载失败，重试 {i + 1}/{self.retries}: {url}")
        raise DownloadError(f"下载失败 {url}: {last}")

    def get_many(self, items: list) -> dict:
        """并发下载。items = [(url, expected_sha256_or_None, key), ...]

        返回 {key: 本地路径}；单个失败不抛异常，失败项记为 None 并打印。
        """
        results: dict = {}
        todo = []
        for url, expected, key in items:
            name = url.rsplit("/", 1)[-1] or "file"
            if expected:
                p = cache_path(self.cache_dir, expected, name)
                if p.exists() and util.sha256_file(p) == expected:
                    results[key] = p
                    continue
            else:
                p = self.cache_dir / "unverified" / name
            todo.append((url, expected, key, p))

        if not todo:
            return results

        util.log("step", f"下载 {len(todo)} 个文件（{self.workers} 并发）")

        def work(item):
            url, expected, key, dest = item
            last = None
            for i in range(self.retries + 1):
                try:
                    return key, _fetch_one(url, dest, expected, self.timeout)
                except Exception as e:
                    last = e
            return key, None

        with cf.ThreadPoolExecutor(max_workers=self.workers) as pool:
            for key, path in pool.map(work, todo):
                if path is None:
                    util.log("err", f"下载失败: {key}（{last}）")
                    results[key] = None
                else:
                    results[key] = path
        return results

    def stats(self) -> dict:
        n, size = 0, 0
        for p in self.cache_dir.rglob("*"):
            if p.is_file():
                n += 1
                size += p.stat().st_size
        return {"files": n, "size": size}

    def prune(self, keep_bytes: int) -> int:
        """按大小裁剪缓存（保留最新的）。返回删除的文件数。"""
        files = sorted((p for p in self.cache_dir.rglob("*") if p.is_file()),
                       key=lambda p: p.stat().st_mtime, reverse=True)
        total = sum(p.stat().st_size for p in files)
        removed = 0
        for p in files:
            if total <= keep_bytes:
                break
            total -= p.stat().st_size
            p.unlink(missing_ok=True)
            removed += 1
        return removed
