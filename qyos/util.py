"""启元 Linux 构建系统 —— 基础工具函数。

提供哈希、归档、下载、日志记录、路径处理等公共能力。
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from pathlib import Path

ARCH = os.uname().machine
ROOT = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------- 日志

_COLORS = {"info": "", "ok": "\033[32m", "warn": "\033[33m",
           "err": "\033[31m", "step": "\033[36m"}
_RESET = "\033[0m"


def log(level: str, msg: str) -> None:
    prefix = {"info": "  ", "ok": "==>", "warn": "!! ", "err": "!!!",
              "step": "-> "}.get(level, "  ")
    c = _COLORS.get(level, "")
    stream = sys.stderr if level in ("warn", "err") else sys.stdout
    print(f"{c}{prefix}{_RESET} {msg}", file=stream, flush=True)


def die(msg: str, code: int = 1) -> "NoReturn":  # type: ignore[valid-type]
    log("err", msg)
    sys.exit(code)


# ---------------------------------------------------------------- 哈希

def sha256_file(path: os.PathLike) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------- 归档

def unpack(archive: Path, dest: Path, strip: int = 1) -> None:
    """解包源码归档。支持 tar.* 与 zip；strip 用于去掉顶层目录。"""
    dest.mkdir(parents=True, exist_ok=True)
    if archive.name.endswith(".zip"):
        import zipfile
        with zipfile.ZipFile(archive) as z:
            z.extractall(dest)
        _apply_strip(dest, strip)
        return
    mode = "r:*"
    with tarfile.open(archive, mode) as tf:
        if strip == 0:
            tf.extractall(dest)
            return
        members = []
        for m in tf.getmembers():
            parts = Path(m.name).parts
            if len(parts) <= strip:
                continue
            m.name = str(Path(*parts[strip:]))
            members.append(m)
        tf.extractall(dest, members=members)


def _apply_strip(dest: Path, strip: int) -> None:
    if strip == 0:
        return
    entries = list(dest.iterdir())
    if len(entries) != 1 or not entries[0].is_dir():
        return
    top = entries[0]
    tmp = dest.parent / (dest.name + ".strip")
    top.rename(tmp)
    for item in tmp.iterdir():
        shutil.move(str(item), str(dest / item.name))
    tmp.rmdir()


def make_tar(src_dir: Path, out_path: Path, comp: str = "gz") -> int:
    """把目录打包成 tar 归档。comp: gz / xz / none。返回条目数。

    逐个条目添加而不是一次 add(dir)：
    某些文件系统（virtiofs、网络挂载、容器 overlay）上，遍历过程中
    目录项可能短暂不可用，整包 add 会直接抛 FileNotFoundError 让构建失败。
    逐条添加时可以对这类条目容错跳过，并如实记录跳过了多少——
    静默吞掉会掩盖真实问题，崩溃又太脆，这里取中间：跳过 + 计数返回。
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    mode = {"gz": "w:gz", "xz": "w:xz", "none": "w"}[comp]

    entries = []
    for root, dirs, files in os.walk(str(src_dir)):
        dirs.sort()
        for d in dirs:
            entries.append(os.path.join(root, d))
        for f in sorted(files):
            entries.append(os.path.join(root, f))

    # 逐个条目添加而非整包 add()：某些文件系统（virtiofs、网络挂载、
    # 容器 overlay）上目录项可能短暂不可用，整包 add 会直接崩掉整个构建。
    # 逐条添加时可以先重试一次；仍然失败就必须报错——
    # 静默跳过会打出一个"文件条目存在但内容为空"的残缺包，
    # 那种包装到机器上才暴露问题，比构建失败危险得多。
    with tarfile.open(out_path, mode) as tf:
        for path in entries:
            arcname = os.path.relpath(path, str(src_dir))
            for attempt in range(3):
                try:
                    tf.add(path, arcname=arcname, recursive=False)
                    break
                except (FileNotFoundError, NotADirectoryError, OSError) as e:
                    if attempt == 2:
                        raise OSError(
                            f"打包 {src_dir} 时无法读取 {arcname}：{e}\n"
                            f"  构建产物在打包阶段不可用，拒绝产出残缺的包。\n"
                            f"  若这是文件系统的偶发问题，重试构建即可；"
                            f"若反复出现，请检查构建目录是否被其他进程改动") from e
                    time.sleep(0.1)
    return len(entries)


def extract_tar(archive: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "r:*") as tf:
        tf.extractall(dest)


# ---------------------------------------------------------------- 下载

def fetch(url: str, dest_dir: Path, expected: str | None = None,
          timeout: int = 300) -> Path:
    """下载源码到缓存目录，返回本地路径。已存在且校验和匹配则跳过。"""
    dest_dir.mkdir(parents=True, exist_ok=True)
    name = url.rsplit("/", 1)[-1] or "source"
    target = dest_dir / name
    if target.exists():
        if expected is None or sha256_file(target) == expected:
            log("info", f"复用缓存 {name}")
            return target
        log("warn", "缓存文件校验和不符，重新下载")
        target.unlink()
    log("step", f"下载 {url}")
    tmp = target.with_suffix(target.suffix + ".part")
    # GitHub 直连常超时：失败时自动走加速镜像
    candidates = [url]
    if "github.com" in url:
        candidates.append("https://ghproxy.net/" + url)
    last_err: Exception | None = None
    for u in candidates:
        req = urllib.request.Request(u, headers={"User-Agent": "qiyuan-fetch/0.1"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f)
            if tmp.read_bytes()[:1] == b"<":
                raise IOError(f"镜像返回 HTML: {u}")
            break
        except Exception as e:
            last_err = e
            tmp.unlink(missing_ok=True)
    else:
        raise last_err if last_err else IOError(f"下载失败: {url}")
    tmp.rename(target)
    if expected is not None:
        got = sha256_file(target)
        if got != expected:
            target.unlink()
            die(f"校验和不符: {name}\n  期望 {expected}\n  实际 {got}")
    return target


def has_network() -> bool:
    try:
        urllib.request.urlopen("https://example.com", timeout=5)
        return True
    except Exception:
        return False


# ---------------------------------------------------------------- 进程

class CmdError(RuntimeError):
    def __init__(self, cmd: str, code: int, out: str):
        super().__init__(f"命令失败({code}): {cmd}")
        self.cmd, self.code, self.out = cmd, code, out


def run(cmd: str, cwd: Path | None = None, env: dict | None = None,
        capture: bool = False, check: bool = True, shell: str = "/bin/bash"):
    """执行命令。capture=True 时返回 (code, stdout+stderr)。"""
    if capture:
        p = subprocess.run([shell, "-c", cmd], cwd=str(cwd) if cwd else None,
                           env=env, capture_output=True, text=True)
        if check and p.returncode != 0:
            raise CmdError(cmd, p.returncode, p.stdout + p.stderr)
        return p.returncode, p.stdout + p.stderr
    else:
        p = subprocess.run([shell, "-c", cmd], cwd=str(cwd) if cwd else None,
                           env=env)
        if check and p.returncode != 0:
            raise CmdError(cmd, p.returncode, "")
        return p.returncode, ""


# ---------------------------------------------------------------- 杂项

def human_size(n: int) -> str:
    for unit in ("B", "K", "M", "G"):
        if n < 1024 or unit == "G":
            return f"{n:.0f}{unit}" if unit != "B" else f"{n}B"
        n /= 1024
    return f"{n:.0f}G"


def read_json(path: Path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)


_warned: set = set()


def _warn_once(msg: str) -> None:
    if msg in _warned:
        return
    _warned.add(msg)
    util_log("warn", msg)


def util_log(level: str, msg: str) -> None:
    """极简日志：util 被低层模块导入，不能反过来依赖 log 的实现细节。"""
    print(f"[util] {msg}", flush=True)


def atomic_write(path: Path, data: bytes) -> None:
    """原子写：写临时文件 → fsync → 重命名 → fsync 目录。

    少了 fsync 就不是真原子：在某些文件系统（网络文件系统、virtiofs、
    容器挂载）上，rename 之后另一个进程仍可能读到旧内容。索引和它的签名
    是分两次写的，一旦读到"新索引 + 旧签名"或反之，就会误报被篡改——
    这种偶发错误最难查，所以这里必须做全。
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    last_err = None
    for attempt in range(3):
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, path)
            # 把目录项也刷下去，否则 rename 本身可能没落地
            try:
                dfd = os.open(str(path.parent), os.O_RDONLY)
                try:
                    os.fsync(dfd)
                finally:
                    os.close(dfd)
            except OSError:
                pass
            # 回读校验：某些虚拟/网络文件系统在 rename 后仍会返回旧内容。
            # 索引和签名分两次写，一旦读到旧内容就会误判"仓库被篡改"，
            # 这是安全相关的假警报，必须主动确认而不是听天由命。
            try:
                if Path(path).read_bytes() == data:
                    return
            except OSError as e:
                last_err = e
            if attempt == 0:
                # 只提示一次：虚拟/网络文件系统上这是常态，刷屏反而淹没真问题
                _warn_once(
                    f"{path.name} 写入后回读不一致（文件系统缓存），已自动重试")
        except Exception as e:
            last_err = e
            try:
                os.unlink(tmp)
            except OSError:
                pass

    # 三次都没写成：绝不能静默返回。
    # 调用方会以为写成功了，后面就拿着"不存在/内容不对"的文件继续跑，
    # 排错时根本想不到是这里。宁可报错。
    try:
        if Path(path).read_bytes() != data:
            raise OSError(
                f"写入 {path} 失败：连续 3 次回读都与待写内容不一致")
    except OSError as e:
        raise OSError(f"写入 {path} 失败：{e}") from e


def timer():
    return time.time()


def fmt_duration(sec: float) -> str:
    m, s = divmod(int(sec), 60)
    if m == 0:
        return f"{s}s"
    h, m = divmod(m, 60)
    return f"{h}h{m}m{s}s" if h else f"{m}m{s}s"
