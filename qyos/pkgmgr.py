"""包管理器核心：安装 / 卸载 / 升级 / 查询 / 校验 / 回滚。

设计要点：
  * 本地已安装包与文件清单存 SQLite，支持反查、孤儿包判断。
  * 事务化：一次操作先算完整变更集 → 下载校验 → 写入，失败按日志回滚。
  * 显式安装与依赖安装分开标记，卸载时可清理孤儿包。
  * 包内脚本（pre/post install）在目标根内以沙箱方式执行。
"""
from __future__ import annotations

import json
import os
import shutil
import sqlite3
import time
from pathlib import Path

from . import deps as depsmod
from . import format as fmt
from . import repo as repomod
from . import transaction as txn
from . import util

# 多个核心包同时提供、内容等价的小工具：安装时后装者覆盖而非报冲突。
_SHARED_OK = {
    "sbin/nologin", "usr/sbin/nologin", "bin/nologin", "usr/bin/nologin",
    "bin/login", "usr/bin/login", "sbin/login", "usr/sbin/login",
    "bin/su", "usr/bin/su",
    "bin/chfn", "usr/bin/chfn", "bin/chsh", "usr/bin/chsh",
    "bin/newgrp", "usr/bin/newgrp", "usr/sbin/adduser", "usr/sbin/deluser",
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS packages (
  name TEXT PRIMARY KEY,
  version TEXT NOT NULL,
  release INTEGER NOT NULL,
  arch TEXT,
  summary TEXT,
  depends TEXT,
  provides TEXT,
  installed_size INTEGER,
  install_time INTEGER,
  reason TEXT,            -- explicit / dependency
  meta TEXT               -- 完整元数据 JSON
);
CREATE TABLE IF NOT EXISTS files (
  path TEXT PRIMARY KEY,
  pkg TEXT NOT NULL,
  sha256 TEXT,
  size INTEGER,
  type TEXT
);
CREATE TABLE IF NOT EXISTS history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER,
  action TEXT,
  detail TEXT
);
"""

# 配置文件：本地改动要保留，不能被静默覆盖
CONFIG_DIRS = ("etc/",)


class PkgError(RuntimeError):
    pass


class DB:
    def __init__(self, root: Path):
        self.root = Path(root)
        dbdir = self.root / "var" / "lib" / "qypkg"
        dbdir.mkdir(parents=True, exist_ok=True)
        self.path = dbdir / "installed.db"
        self.conn = sqlite3.connect(self.path)
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(SCHEMA)
        self._migrate()
        self.conn.commit()

    # -- 包 --------------------------------------------------------

    def _migrate(self) -> None:
        """补齐后加的列。

        CREATE TABLE IF NOT EXISTS 对已存在的表什么都不做，
        所以新增列必须显式迁移。不迁移的后果不是报错，而是静默退化：
        config 读不到 → 升级时无法判断哪些文件被改过 →
        全部保守判成冲突，用户每次升级都收到一堆 .qynew。
        这种"不报错但行为不对"的问题比崩溃更难发现。
        """
        cols = {r["name"] for r in self.conn.execute(
            "PRAGMA table_info(files)")}
        if cols and "config" not in cols:
            self.conn.execute(
                "ALTER TABLE files ADD COLUMN config INTEGER DEFAULT 0")
            self.conn.commit()

    def installed(self) -> dict:
        return {r["name"]: dict(r) for r in
                self.conn.execute("SELECT * FROM packages")}

    def get(self, name: str):
        r = self.conn.execute("SELECT * FROM packages WHERE name=?", (name,)).fetchone()
        return dict(r) if r else None

    def add_pkg(self, meta: fmt.Meta, files: list, reason: str) -> None:
        self.conn.execute(
            "INSERT OR REPLACE INTO packages VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (meta.name, meta.version, meta.release, meta.arch, meta.summary,
             json.dumps(meta.depends), json.dumps(meta.provides),
             meta.installed_size, int(time.time()), reason,
             meta.to_json().decode()))
        for f in files:
            cfg = f["config"] if isinstance(f, dict) else getattr(f, "config", False)
            self.conn.execute(
                "INSERT OR REPLACE INTO files VALUES (?,?,?,?,?,?)",
                (f["path"] if isinstance(f, dict) else f.path,
                 meta.name,
                 f["sha256"] if isinstance(f, dict) else f.sha256,
                 f["size"] if isinstance(f, dict) else f.size,
                 f["type"] if isinstance(f, dict) else f.type,
                 1 if cfg else 0))
        self.conn.commit()

    def remove_pkg(self, name: str) -> None:
        self.conn.execute("DELETE FROM packages WHERE name=?", (name,))
        self.conn.execute("DELETE FROM files WHERE pkg=?", (name,))
        self.conn.commit()

    def owner_of(self, path: str):
        r = self.conn.execute("SELECT pkg FROM files WHERE path=?", (path,)).fetchone()
        return r["pkg"] if r else None

    def files_of(self, name: str) -> list:
        return [dict(r) for r in self.conn.execute(
            "SELECT * FROM files WHERE pkg=? ORDER BY path", (name,))]

    def dependents(self, name: str) -> list:
        """找出依赖 name 的已安装包。"""
        out = []
        for r in self.conn.execute("SELECT name, depends FROM packages"):
            for d in json.loads(r["depends"] or "[]"):
                if depsmod.parse_dep(d).name == name and r["name"] != name:
                    out.append(r["name"])
        return sorted(set(out))

    def log(self, action: str, detail: str) -> None:
        self.conn.execute("INSERT INTO history (ts, action, detail) VALUES (?,?,?)",
                          (int(time.time()), action, detail))
        self.conn.commit()


class Manager:
    def __init__(self, root: Path, repo_dir: Path | None = None,
                 pubkey: Path | None = None, dry_run: bool = False,
                 allow_unsigned: bool = False, auto_recover: bool = True,
                 arch: str | None = None):
        self.root = Path(root)
        self.repo_dir = Path(repo_dir) if repo_dir else None
        self.arch = arch  # None = 宿主架构默认
        self.pubkey = Path(pubkey) if pubkey else None
        self.dry_run = dry_run
        self.allow_unsigned = allow_unsigned
        # 启动即恢复：上次断电/中断留下的半成品事务，先把系统还原干净
        if auto_recover:
            txn.recover(self.root)
        self.db = DB(self.root)
        self._index = None

    # -- 仓库 ------------------------------------------------------

    @property
    def index(self) -> dict:
        if self._index is None:
            if not self.repo_dir:
                raise PkgError("未指定仓库目录")
            self._index = repomod.load_index(
                self.repo_dir, arch=self.arch or util.ARCH,
                pub_path=self.pubkey,
                require_sig=not self.allow_unsigned)
        return self._index

    def available(self, name: str) -> dict | None:
        return repomod.find_in_index(self.index, name)

    # -- 安装 ------------------------------------------------------

    def _pkgfile(self, entry: dict) -> Path:
        p = self.repo_dir / entry["arch"] / entry["filename"]
        if not p.exists():
            raise PkgError(f"仓库中缺少包文件: {entry['filename']}")
        if util.sha256_file(p) != entry["sha256"]:
            raise PkgError(f"包 {entry['filename']} 与索引记录的哈希不符，拒绝安装")
        return p

    def install(self, names: list, as_explicit: bool = True,
                reinstall: bool = False) -> None:
        plan = self.plan_install(names, as_explicit, reinstall)
        if not plan:
            util.log("ok", "没有需要安装的包")
            return
        total = sum(e["installed_size"] for _, e, _ in plan)
        util.log("ok", f"将安装 {len(plan)} 个包，占用约 {util.human_size(total)}")
        for n, e, _ in plan:
            util.log("info", f"  {e['pkgid']}  {e['summary']}")
        if self.dry_run:
            util.log("warn", "演练模式，未实际写入")
            return
        self._check_space(total)
        # 系统级事务：中途失败或断电，下次启动自动还原
        with txn.Transaction(self.root, "install", " ".join(names)) as t:
            for n, entry, explicit in plan:
                self._install_one(entry, "explicit" if explicit else "dependency", t)

    def plan_install(self, names: list, as_explicit: bool = True,
                     reinstall: bool = False) -> list:
        inst = self.db.installed()
        u = depsmod.Universe()
        for e in self.index["packages"]:
            u.add(type("P", (), {"name": e["name"], "version": e["version"],
                                 "release": e.get("release", 1),
                                 "provides": e.get("provides") or [],
                                 "depends": e.get("depends") or []})())
        try:
            order = u.resolve(names, installed=inst)
        except depsmod.DepError as e:
            raise PkgError(str(e))

        plan = []
        for n in order:
            if n in inst and not reinstall:
                util.log("info", f"{n} 已安装，跳过")
                continue
            entry = self.available(n)
            if entry is None:
                raise PkgError(f"仓库中没有包: {n}")
            plan.append((n, entry, as_explicit or n in names))
        return plan

    def _check_space(self, need_bytes: int) -> None:
        """升级前检查磁盘空间，不够就别开始——装一半没空间最麻烦。"""
        try:
            st = os.statvfs(str(self.root))
            free = st.f_bavail * st.f_frsize
        except Exception:
            return
        # 快照还要占一份，按两倍算
        if free < need_bytes * 2 + (64 << 20):
            raise PkgError(
                f"磁盘空间不足：需要约 {util.human_size(need_bytes * 2)}"
                f"（含回滚快照），可用 {util.human_size(free)}")

    def _install_one(self, entry: dict, reason: str,
                     t: "txn.Transaction | None" = None) -> None:
        pkgfile = self._pkgfile(entry)
        pkg = fmt.read_package(pkgfile)
        if not pkg.verify():
            raise PkgError(f"包校验失败: {pkgfile}")
        meta = pkg.meta

        from . import pkgops as PO
        # 0. 升级前先取出旧版本的配置文件原始校验和。
        # 必须在覆盖之前取——写完之后旧版本就没了，
        # 也就无从判断"用户到底改没改过"
        db_orig = {}
        old_inst = self.db.get(meta.name)
        if old_inst:
            for f in self.db.files_of(meta.name):
                if getattr(f, "config", False) or (
                        isinstance(f, dict) and f.get("config")):
                    fp = f["path"] if isinstance(f, dict) else f.path
                    fs = f["sha256"] if isinstance(f, dict) else f.sha256
                    db_orig[fp] = fs

        # 1. 冲突与文件占用检查
        for c in meta.conflicts:
            cn = depsmod.parse_dep(c).name
            if self.db.get(cn):
                raise PkgError(f"{meta.name} 与已安装的 {cn} 冲突")
        for f in meta.files:
            if f.type == "dir":
                continue   # 目录由多个包共享，不算冲突
            if f.type == "symlink" and f.path in ("bin", "usr/sbin", "sbin", "lib", "lib64", "usr/lib"):
                continue   # FHS 合并布局符号链（/bin→/usr/bin 等）多包共享
            owner = self.db.owner_of(f.path)
            if owner and owner != meta.name:
                if f.path.endswith("share/info/dir"):
                    continue
                # xorgproto 收编了各 X 库自带的协议头，版本差异属正常演进，
                # 后装者（具体库）覆盖是各发行版的通行做法；其余冲突仍拒绝
                if f.path.startswith("usr/share/doc/") or f.path.startswith("usr/include/X11/extensions/"):
                    print(f"[覆盖] {owner} 的同名协议头: {f.path}")
                    continue
                # nologin 之类被多个核心包同时提供的小工具：后装者覆盖是
                # 各发行版通行做法（内容等价），不应阻断安装。
                if f.path in _SHARED_OK:
                    print(f"[覆盖] {owner} 的同名文件（共享工具）: {f.path}")
                    continue
                raise PkgError(f"文件冲突: {f.path} 已属于 {owner}")

        # 1b. pre_install：通常是前置检查（目录、用户、内核模块）。
        # 它失败就不该继续装——装到一半发现前置条件不满足更难收拾
        pre = PO.run_scripts(meta, self.root, [PO.PRE_INSTALL])
        for r in pre:
            if not r.ok:
                raise PkgError(
                    f"{meta.name} 的 pre_install 失败，中止安装: {r.error[:200]}")

        # 2. 写入（先解到暂存区，再移动，保证失败可回滚）
        written: list = []
        staging = self.root / "var" / "lib" / "qypkg" / "staging" / meta.name
        if staging.exists():
            shutil.rmtree(staging)
        try:
            pkg.extract(staging, check_hashes=True)
            for f in meta.files:
                dst = self.root / f.path
                src = staging / f.path
                # 配置文件不在这里覆盖，交给下面的三方比对处理
                if getattr(f, "config", False):
                    continue
                if f.type == "dir":
                    dst.mkdir(parents=True, exist_ok=True)
                    try:
                        os.chmod(dst, f.mode)
                    except OSError:
                        pass
                    continue
                dst.parent.mkdir(parents=True, exist_ok=True)
                if dst.exists() or dst.is_symlink():
                    # 覆盖前先快照，系统级回滚靠这个
                    if t is not None:
                        t.backup(f.path)
                    if dst.is_symlink() or dst.is_file():
                        dst.unlink()
                    else:
                        shutil.rmtree(dst)
                elif t is not None:
                    # 原本不存在，回滚时要删掉
                    t.backup(f.path)
                shutil.move(str(src), str(dst))
                # 符号链接在 Linux 上权限恒为 777，不能 chmod（会跟随目标，
                # 且目标可能尚未就位）；其余按包内记录的权限位设置
                if f.type != "symlink":
                    os.chmod(dst, f.mode)
                written.append(f.path)
            # 2b. 配置文件三方比对。
            # 无条件覆盖 /etc 下的文件等于每次升级都毁掉用户的配置——
            # 改过的 sshd_config、fstab 全没了
            states = PO.plan_configs(self.root, meta, db_orig)
            if states:
                conflicts = PO.apply_configs(self.root, staging, states)
                replaced = sum(1 for x in states if x.action == "replace")
                kept = sum(1 for x in states if x.action == "keep")
                util.log("info", f"配置文件：采用新版 {replaced}，"
                                 f"保留本地 {kept}，冲突 {len(conflicts)}")
                for path, newp, why in conflicts:
                    util.log("warn", f"{path} 本地改过且新版本也有变化")
                    util.log("info", f"  你的版本已保留，新版本：{newp}")
                    util.log("info", f"  请自行合并后删除 {newp}")

            # 2c. 系统用户/组。声明式而非脚本里 useradd：可审计、幂等
            if meta.sysusers:
                try:
                    users = [PO.SysUser(**u) if isinstance(u, dict) else u
                             for u in meta.sysusers]
                    done = PO.apply_sysusers(self.root, users)
                    if done:
                        util.log("info", f"已创建 {'、'.join(done)}")
                except Exception as e:
                    util.log("warn", f"创建系统用户失败（不影响安装）: {e}")

            # 2d. alternatives：多个包提供同一个通用命令
            for a in (meta.alternatives or []):
                try:
                    alt = PO.register_alt(self.root, a["name"], a["link"],
                                          meta.name, a["target"])
                    PO.apply_alt(self.root, alt)
                    util.log("info", f"/{a['link'].lstrip('/')} → {a['target']}")
                except Exception as e:
                    util.log("warn", f"注册 alternative 失败: {e}")

        except Exception as e:
            for p in written:
                fp = self.root / p
                if fp.is_file() or fp.is_symlink():
                    fp.unlink(missing_ok=True)
            raise PkgError(f"{meta.name} 安装失败并已回滚: {e}")
        finally:
            shutil.rmtree(staging, ignore_errors=True)
        # 3. post_install：文件已经落盘，失败不该把系统留在半装状态，
        #    所以只警告。它通常是"生成 host key""更新缓存"这类动作
        PO.run_scripts(meta, self.root, [PO.POST_INSTALL])

        # 4. 触发器：声明式的系统动作（装字体→fc-cache）。
        #    能用触发器表达的就不该用脚本——可审计、可预测
        trig = PO.triggers_for(meta)
        if trig:
            res = PO.run_triggers(trig, self.root)
            for name, okk, err in res:
                if okk is False:
                    util.log("warn", f"触发器 {name} 失败（{PO.TRIGGERS[name]['why']}）: {err}")
                elif okk:
                    util.log("info", f"已触发 {name}")

        self.db.add_pkg(meta, meta.files, reason)
        self.db.log("install", meta.pkgid)
        util.log("ok", f"已安装 {meta.pkgid}")

    # -- 卸载 ------------------------------------------------------

    def remove(self, names: list, recursive: bool = False,
               clean_orphans: bool = False) -> None:
        inst = self.db.installed()
        targets = set()
        for n in names:
            if n not in inst:
                util.log("warn", f"{n} 未安装，跳过")
                continue
            targets.add(n)
        if recursive:
            stack = list(targets)
            while stack:
                cur = stack.pop()
                for dep in self.db.dependents(cur):
                    if dep not in targets:
                        targets.add(dep)
                        stack.append(dep)

        # 检查是否有未一起卸载的依赖者
        for t in list(targets):
            deps_on = [d for d in self.db.dependents(t) if d not in targets]
            if deps_on:
                raise PkgError(
                    f"{t} 仍被依赖: {', '.join(deps_on)}（加 -R 一起卸载）")

        if self.dry_run:
            util.log("warn", "演练模式，未实际删除")
            return
        with txn.Transaction(self.root, "remove", " ".join(sorted(targets))) as t:
            for name in sorted(targets):
                self._remove_one(name, t)

        if clean_orphans:
            self.clean_orphans()

    def _remove_one(self, name: str, t: "txn.Transaction | None" = None) -> None:
        from . import pkgops as PO
        rec = self.db.get(name)
        if not rec:
            return
        files = self.db.files_of(name)

        # pre_remove 在删文件之前跑：它通常是"停服务""备份数据"，
        # 文件删完再跑就没意义了
        try:
            meta_like = type("M", (), {
                "name": name,
                "scripts": (rec.get("scripts") or {}) if isinstance(rec, dict)
                else {},
            })()
            PO.run_scripts(meta_like, self.root, [PO.PRE_REMOVE])
        except Exception as e:
            util.log("warn", f"{name} 的 pre_remove 失败（继续卸载）: {e}")

        # 注销 alternatives：提供者没了，通用链接要指向别的提供者
        try:
            alts = PO.load_alts(self.root)
            for aname, d in list(alts.items()):
                if name in (d.get("providers") or {}):
                    PO.unregister_alt(self.root, aname, name)
                    nd = PO.load_alts(self.root).get(aname)
                    if nd:
                        PO.apply_alt(self.root, PO.Alternative(
                            aname, nd["link"], nd["providers"], nd["current"]))
        except Exception as e:
            util.log("warn", f"清理 alternative 失败: {e}")

        # 先删文件（目录最后删），再删记录
        for f in files:
            if f["type"] == "dir":
                continue
            p = self.root / f["path"]
            if p.is_symlink() or p.is_file():
                if t is not None:
                    t.backup(f["path"])
                p.unlink(missing_ok=True)
        for f in reversed(files):
            if f["type"] != "dir":
                continue
            p = self.root / f["path"]
            if p.is_dir() and not any(p.iterdir()):
                try:
                    p.rmdir()
                except OSError:
                    pass
        try:
            PO.run_scripts(meta_like, self.root, [PO.POST_REMOVE])
        except Exception:
            pass
        self.db.remove_pkg(name)
        self.db.log("remove", name)
        util.log("ok", f"已卸载 {name}")

    def clean_orphans(self) -> None:
        """清理作为依赖装进来、但已无人需要的包。"""
        removed = 0
        while True:
            inst = self.db.installed()
            orphan = [n for n, r in inst.items()
                      if r["reason"] == "dependency"
                      and not any(self.db.dependents(n))]
            if not orphan:
                break
            for n in orphan:
                self._remove_one(n)
                removed += 1
        if removed:
            util.log("ok", f"清理孤儿包 {removed} 个")
        else:
            util.log("info", "没有孤儿包")

    # -- 升级 ------------------------------------------------------

    def plan_upgrade(self) -> list:
        inst = self.db.installed()
        out = []
        for e in self.index["packages"]:
            cur = inst.get(e["name"])
            if not cur:
                continue
            if self._is_newer(e, cur):
                out.append((e["name"], f"{cur['version']}-{cur['release']}",
                            e["pkgid"]))
        return out

    @staticmethod
    def _is_newer(entry: dict, cur: dict) -> bool:
        a = (str(cur["version"]), int(cur["release"]))
        b = (str(entry["version"]), int(entry.get("release", 1)))
        return depsmod.version_cmp(b[0], ">", a[0]) or (
            b[0] == a[0] and b[1] > a[1])

    def precheck_upgrade(self, plan: list) -> list:
        """升级前检查。返回问题列表，非空就不该开始。

        三件事最容易在升级后炸掉系统：
          1. 新版引入的依赖在仓库里没有
          2. 新版与已装的其他包冲突
          3. 磁盘空间不够（快照还要占一份）
        """
        problems = []
        inst = self.db.installed()
        u = depsmod.Universe()
        for e in self.index["packages"]:
            u.add(type("P", (), {"name": e["name"], "version": e["version"],
                                 "release": e.get("release", 1),
                                 "provides": e.get("provides") or [],
                                 "depends": e.get("depends") or []})())
        for name, _, _ in plan:
            entry = self.available(name)
            if not entry:
                problems.append(f"{name}: 仓库中已无此包")
                continue
            for d in entry.get("depends") or []:
                dep = depsmod.parse_dep(d)
                if dep.name in inst:
                    continue
                if u.provider_of(dep) is None:
                    problems.append(f"{name}: 新依赖 {d} 在仓库中找不到")
            for c in entry.get("conflicts") or []:
                cn = depsmod.parse_dep(c).name
                if cn in inst and cn != name:
                    problems.append(f"{name}: 与已安装的 {cn} 冲突")
        need = sum(self.available(n)["installed_size"] for n, _, _ in plan
                   if self.available(n))
        try:
            st = os.statvfs(str(self.root))
            if st.f_bavail * st.f_frsize < need * 2 + (64 << 20):
                problems.append(
                    f"磁盘空间不足：需要约 {util.human_size(need * 2)}（含回滚快照），"
                    f"可用 {util.human_size(st.f_bavail * st.f_frsize)}")
        except Exception:
            pass
        return problems

    def upgrade(self, names: list | None = None) -> None:
        plan = [p for p in self.plan_upgrade()
                if not names or p[0] in names]
        if not plan:
            util.log("ok", "系统已是最新")
            return
        util.log("ok", f"{len(plan)} 个包可升级")
        for n, old, new in plan:
            util.log("info", f"  {n}: {old} -> {new}")

        problems = self.precheck_upgrade(plan)
        if problems:
            util.log("err", "升级前检查未通过，已中止：")
            for p in problems:
                util.log("err", f"  {p}")
            raise PkgError("升级前检查未通过")

        if self.dry_run:
            util.log("warn", "演练模式，未实际写入")
            return

        # 整批升级是一个事务：任何一个包失败，全部回滚到升级前
        with txn.Transaction(self.root, "upgrade",
                             " ".join(n for n, _, _ in plan)) as t:
            for n, _, _ in plan:
                entry = self.available(n)
                old = self.db.get(n)
                self._install_one(entry, old["reason"], t)
        util.log("ok", f"升级完成，快照可用于回滚")

    # -- 查询 / 校验 ------------------------------------------------

    def list_installed(self) -> list:
        return sorted(self.db.installed().values(), key=lambda r: r["name"])

    def search(self, keyword: str) -> list:
        kw = keyword.lower()
        return [e for e in self.index["packages"]
                if kw in e["name"].lower() or kw in (e.get("summary") or "").lower()]

    def info(self, name: str) -> dict | None:
        return self.available(name) or self.db.get(name)

    def verify(self, name: str | None = None) -> list:
        """校验已安装包的文件是否被改动。"""
        problems = []
        targets = [name] if name else sorted(self.db.installed())
        for n in targets:
            rec = self.db.get(n)
            if not rec:
                continue
            meta = fmt.Meta.from_json(rec["meta"].encode())
            for f in meta.files:
                p = self.root / f.path
                if f.type == "file":
                    if not p.exists():
                        problems.append((n, f.path, "缺失"))
                    elif util.sha256_file(p) != f.sha256:
                        problems.append((n, f.path, "已改动"))
                elif f.type == "symlink":
                    if not p.is_symlink():
                        problems.append((n, f.path, "链接丢失"))
        return problems

    def history(self, limit: int = 20) -> list:
        return [dict(r) for r in self.db.conn.execute(
            "SELECT * FROM history ORDER BY id DESC LIMIT ?", (limit,))]
