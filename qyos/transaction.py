"""事务与系统级原子升级、回滚。

单个包的安装已经能回滚（pkgmgr 里的 written 列表），但一次升级往往横跨几十个包：
装到第 30 个失败，前 29 个已经写进系统——这在中途断电时就是一台半残的机器。
所以升级必须是系统级事务。

做法：文件级写前快照 + 事务日志（journal）

    var/lib/qypkg/
      journal/
        <txid>.json      事务日志：要改哪些文件、备份在哪、动作是什么
      snapshots/
        <txid>/          被覆盖或删除的文件的原始内容（按原路径镜像）
      lock               并发锁，同一时刻只允许一个事务

事务状态机：pending → committed / rolled_back / aborted

    begin()     建 journal，记录 txid
    backup()    每次覆盖或删除前，把原文件复制进快照区并记一条日志
    commit()    全部成功 → 清 journal，保留快照一段时间供手动回滚
    rollback()  任一步失败或断电重启后发现 pending → 按日志逆序还原

断电恢复：下次任何命令启动前调用 recover()，发现 pending 事务就自动回滚。
这是"升级中断后系统仍可用"的关键，也是产品级和玩具的分界线。
"""
from __future__ import annotations

import json
import os
import shutil
import time
import uuid
from pathlib import Path

from . import util

STATE_PENDING = "pending"
STATE_COMMITTED = "committed"
STATE_ROLLED_BACK = "rolled_back"


class TxnError(RuntimeError):
    pass


class Transaction:
    """一次系统级变更。作为上下文管理器使用：

        with Transaction(root, "upgrade") as tx:
            tx.backup("usr/bin/foo")     # 覆盖或删除前调用
            ...写入...
        # 正常退出自动 commit；抛异常自动 rollback
    """

    def __init__(self, root: Path, action: str, detail: str = "",
                 keep_snapshots: int = 3):
        self.root = Path(root)
        self.action = action
        self.detail = detail
        self.txid = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6]
        self.base = self.root / "var" / "lib" / "qypkg"
        self.jdir = self.base / "journal"
        self.sdir = self.base / "snapshots" / self.txid
        for d in (self.jdir, self.base / "snapshots"):
            d.mkdir(parents=True, exist_ok=True)
        self.jpath = self.jdir / f"{self.txid}.json"
        self.entries: list = []
        self.state = STATE_PENDING
        self.keep = keep_snapshots
        self._lock = None

    # -- 锁 --------------------------------------------------------

    def acquire_lock(self) -> None:
        lock = self.base / "lock"
        self.base.mkdir(parents=True, exist_ok=True)
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            with os.fdopen(fd, "w") as f:
                f.write(f"{self.txid} {self.action} pid={os.getpid()}\n")
            self._lock = lock
        except FileExistsError:
            raise TxnError(
                f"另一个事务正在进行（{lock.read_text().strip()}）。"
                f"若确认没有进程在跑，删除 {lock} 后重试")

    def release_lock(self) -> None:
        if self._lock and self._lock.exists():
            self._lock.unlink()
            self._lock = None

    # -- 生命周期 ---------------------------------------------------

    def __enter__(self) -> "Transaction":
        self.acquire_lock()
        self._write_journal()
        util.log("step", f"事务 {self.txid} 开始（{self.action}）")
        return self

    def __exit__(self, exc_type, exc, tb):
        if exc_type is None:
            self.commit()
        else:
            util.log("warn", f"事务中断: {exc}")
            self.rollback()
        self.release_lock()
        return False

    # -- 快照 -------------------------------------------------------

    def backup(self, relpath: str) -> None:
        """在覆盖或删除 relpath 之前调用，保存原始内容。

        文件不存在时记为 absent（回滚时删掉新写入的文件）。
        """
        src = self.root / relpath
        if not src.exists() and not src.is_symlink():
            self._record(relpath, "absent", "", "file")
            return
        if src.is_symlink():
            self._record(relpath, "symlink", os.readlink(src), "symlink")
            return
        if src.is_dir():
            self._record(relpath, "dir", "", "dir")
            return
        snap = self.sdir / relpath
        snap.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, snap, follow_symlinks=False)
        self._record(relpath, "file", util.sha256_file(src), "file")

    def _record(self, relpath: str, kind: str, extra: str, ftype: str) -> None:
        self.entries.append({"path": relpath, "kind": kind, "extra": extra,
                             "type": ftype})
        self._write_journal()

    def _write_journal(self) -> None:
        util.atomic_write(self.jpath, json.dumps({
            "txid": self.txid, "action": self.action, "detail": self.detail,
            "state": self.state, "started": int(time.time()),
            "root": str(self.root), "entries": self.entries,
        }, ensure_ascii=False, indent=1).encode())

    # -- 提交 / 回滚 -------------------------------------------------

    def commit(self) -> None:
        self.state = STATE_COMMITTED
        # 快照目录里留一份说明：只靠目录名看不出这次变更是升级还是安装
        self.sdir.mkdir(parents=True, exist_ok=True)
        util.atomic_write(self.sdir / ".txn.json", json.dumps({
            "txid": self.txid, "action": self.action, "detail": self.detail,
            "committed": int(time.time()), "entries": self.entries,
        }, ensure_ascii=False, indent=1).encode())
        self._write_journal()
        self.jpath.unlink(missing_ok=True)
        self._prune_snapshots()
        util.log("ok", f"事务 {self.txid} 已提交（快照保留供回滚）")

    def rollback(self) -> int:
        """按日志逆序还原。返回还原的文件数。"""
        restored = 0
        for e in reversed(self.entries):
            dst = self.root / e["path"]
            snap = self.sdir / e["path"]
            try:
                if e["kind"] == "absent":
                    # 原本不存在 → 删掉这次写入的东西
                    if dst.is_file() or dst.is_symlink():
                        dst.unlink()
                    elif dst.is_dir():
                        shutil.rmtree(dst, ignore_errors=True)
                else:
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    if dst.exists() or dst.is_symlink():
                        if dst.is_dir() and not dst.is_symlink():
                            shutil.rmtree(dst, ignore_errors=True)
                        else:
                            dst.unlink()
                    if e["kind"] == "symlink":
                        dst.symlink_to(e["extra"])
                    elif e["kind"] == "dir":
                        dst.mkdir(parents=True, exist_ok=True)
                    else:
                        shutil.copy2(snap, dst, follow_symlinks=False)
                restored += 1
            except Exception as ex:
                util.log("err", f"回滚 {e['path']} 失败: {ex}")
        self.state = STATE_ROLLED_BACK
        self._write_journal()
        self.jpath.unlink(missing_ok=True)
        util.log("warn", f"事务 {self.txid} 已回滚（还原 {restored} 个文件）")
        return restored

    def _prune_snapshots(self) -> None:
        """只保留最近 keep 份快照，避免无限占用磁盘。"""
        snaps = sorted((self.base / "snapshots").iterdir(),
                       key=lambda p: p.name, reverse=True)
        for old in snaps[self.keep:]:
            shutil.rmtree(old, ignore_errors=True)


# ---------------------------------------------------------------- 恢复

def pending_transactions(root: Path) -> list:
    jdir = Path(root) / "var" / "lib" / "qypkg" / "journal"
    if not jdir.exists():
        return []
    out = []
    for p in sorted(jdir.glob("*.json")):
        try:
            out.append(json.loads(p.read_text()))
        except Exception:
            continue
    return out


def recover(root: Path, auto: bool = True) -> int:
    """启动时调用：发现未完成的事务就回滚。

    这是断电/中断后系统仍能开机的保障。返回回滚的事务数。
    """
    pend = pending_transactions(root)
    if not pend:
        return 0
    n = 0
    for j in pend:
        util.log("warn", f"发现未完成的事务 {j['txid']}（{j['action']}），"
                         f"共 {len(j['entries'])} 项变更")
        if not auto:
            continue
        tx = Transaction(root, j["action"], j["detail"])
        tx.txid = j["txid"]
        tx.jpath = (root / "var/lib/qypkg/journal" / f"{j['txid']}.json")
        tx.sdir = root / "var/lib/qypkg/snapshots" / j["txid"]
        tx.entries = j["entries"]
        tx.rollback()
        n += 1
    return n


def list_snapshots(root: Path) -> list:
    """列出可回滚的快照，带动作说明。"""
    sdir = Path(root) / "var" / "lib" / "qypkg" / "snapshots"
    if not sdir.exists():
        return []
    out = []
    for p in sorted((x for x in sdir.iterdir() if x.is_dir()), reverse=True):
        meta = p / ".txn.json"
        action, detail, when = "-", "", ""
        if meta.exists():
            try:
                d = json.loads(meta.read_text())
                action = d.get("action", "-")
                detail = d.get("detail", "")
                when = time.strftime("%m-%d %H:%M",
                                     time.localtime(d.get("committed", 0)))
            except Exception:
                pass
        out.append({"txid": p.name, "action": action, "detail": detail,
                    "time": when, "files": sum(
                        1 for f in p.rglob("*") if f.is_file()
                        and f.name != ".txn.json")})
    return out


def rollback_to(root: Path, txid: str) -> int:
    """手动回滚到某个已提交事务之前的快照。"""
    sdir = Path(root) / "var" / "lib" / "qypkg" / "snapshots" / txid
    if not sdir.exists():
        raise TxnError(f"快照不存在: {txid}")
    meta = sdir / ".txn.json"
    entries = []
    if meta.exists():
        try:
            entries = json.loads(meta.read_text()).get("entries", [])
        except Exception:
            entries = []
    if not entries:
        # 没有记录就从快照目录反推文件清单
        for p in sorted(sdir.rglob("*")):
            if p.is_dir() or p.name == ".txn.json":
                continue
            rel = p.relative_to(sdir)
            entries.append({"path": str(rel), "kind": "file",
                            "extra": "", "type": "file"})
    tx = Transaction(root, "manual-rollback", f"回滚到 {txid}")
    tx.txid = txid
    tx.sdir = sdir
    tx.entries = entries
    return tx.rollback()
