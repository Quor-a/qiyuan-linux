"""构建器：配方 → 源码 → 沙箱构建 → 独立安装目录 → .qyp 包。

一次构建的完整流程：

    fetch      下载/复用源码并校验 sha256
    prepare    解包到 builddir
    build      在隔离环境中执行配方的 build()
    package    执行 package()，产物只落进 destdir（fakeroot 位置）
    scan       扫描 destdir 生成文件清单
    pack       写入 .qyp（可选签名）
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import traceback
from pathlib import Path

from . import format as fmt
from . import recipe as recipemod
from . import sandbox as sandboxmod
from . import util


class BuildError(RuntimeError):
    """构建失败。"""


class BuildPending(RuntimeError):
    """配方尚未就绪（上游源码地址没填），不该被当成构建失败。

    单列一类而不是复用 BuildError，是因为"还没写"和"写错了"是两回事：
    全量构建时前者该跳过并提醒，后者才该停下来。
    混在一起会让全量构建永远红着，真失败反而被淹没。
    """
    pass

DEFAULT_LAYOUT = {
    "src": "var/src",
    "pkgs": "var/pkgs",
    "cache": "var/cache",
    "work": "var/work",
}


class BuildContext:
    """传给配方 build()/package() 的上下文。"""

    def __init__(self, rec, paths: dict, sb: "sandboxmod.Sandbox", log,
                 cross=None):
        self.recipe = rec
        self.name = rec.name
        self.version = rec.version
        self.srcdir = paths["srcdir"]
        self.builddir = paths["builddir"]
        self.destdir = paths["destdir"]
        self.pkgdir = paths["pkgdir"]
        self.jobs = sb.jobs
        self.sandbox = sb
        self._log = log
        self.env_extra: dict = {}
        self.out_of_tree_mode = False
        self.cross = cross                      # crosstool.Triple 或 None
        if cross is not None and cross.cross:
            # 交叉编译环境下，配方的 ctx.run 直接就能用目标工具链。
            # 不注入的话配方得自己写 CC=xxx，177 个包必然写漏。
            from . import crosstool as CT
            ce = CT.CrossEnv(cross,
                             sysroot=paths.get("sysroot_path"))
            self.env_extra.update(ce.env())
            self._log(f"[交叉] host={cross.host} "
                      f"CC={self.env_extra.get('CC', '?')}")

    def log(self, msg: str) -> None:
        """配方里输出一行说明。

        ctx.run 的输出自带命令，但纯说明性的内容（"这步不需要编译"）
        需要有地方说出来——否则配方里出现 pass 时，
        看日志的人分不清是忘了写还是本来就不需要写。
        """
        self._log(msg)

    def configure_args(self) -> list:
        """给 autotools 的 --build/--host/--target 参数。

        配方里写成 ctx.run(f"./configure --prefix=/usr "
                           f"{' '.join(ctx.configure_args())}")。
        只给 --host 会被当成原生编译，必须配对给。
        """
        if self.cross is None:
            return []
        from . import crosstool as CT
        return CT.configure_args(
            self.cross, getattr(self, "sysroot", None), self.name)

    def write_cmake_toolchain(self) -> str | None:
        """生成 CMake 工具链文件，返回路径。交叉编译时配方要用它。"""
        if self.cross is None or not self.cross.cross:
            return None
        from . import crosstool as CT
        text = CT.cmake_toolchain(self.cross, getattr(self, "sysroot", None))
        p = self.builddir / "qiyuan-cross.cmake"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return str(p)

    # -- 供配方调用 ------------------------------------------------

    def run(self, cmd: str, cwd=None, net: bool | None = None, check=True,
            capture=False):
        """默认在源码目录内构建（多数上游项目如此）。
        需要分离构建（out-of-tree）的配方先调用 out_of_tree()。"""
        self._log(cmd)
        base = self.srcdir if not self.out_of_tree_mode else self.builddir
        return self.sandbox.run(cmd, cwd=Path(cwd) if cwd else base,
                                env=self.env_extra, net=net, check=check,
                                capture=capture)

    def out_of_tree(self) -> None:
        """切换到分离构建目录（autotools/cmake 常用）。"""
        self.out_of_tree_mode = True
        self.builddir.mkdir(parents=True, exist_ok=True)

    def env(self, key=None, value=None, **kw):
        """设置构建环境变量。支持 ctx.env("CC", "gcc") 与 ctx.env(CC="gcc")。"""
        if key is not None:
            self.env_extra[str(key)] = str(value)
        self.env_extra.update({k: str(v) for k, v in kw.items()})

    def install_file(self, src, dst, mode=0o644):
        """把单个文件放进 destdir。src 相对路径按源码目录解析。"""
        p = Path(src)
        if not p.is_absolute():
            p = self.srcdir / p
        target = self.destdir / str(dst).lstrip("/")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, target)
        os.chmod(target, mode)

    def install_dir(self, src, dst):
        p = Path(src)
        if not p.is_absolute():
            p = self.srcdir / p
        target = self.destdir / str(dst).lstrip("/")
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(p, target)

    def check_no_host_libs(self, relpaths: list) -> None:
        """自举判据：确认产物没有链接宿主的库。

        这一条是"自举真假"的分界线——如果编出来的 libc 还是链接宿主的，
        那整个自举就是假的，后面所有包本质上仍是别人的。
        """
        host_markers = ("/lib/x86_64-linux-gnu", "/usr/lib/x86_64-linux-gnu",
                        "/nix/store", "/lib64/", "/usr/lib64/")
        bad = []
        for rel in relpaths:
            p = self.destdir / str(rel).lstrip("/")
            if not p.exists():
                continue
            try:
                out = subprocess.run(["objdump", "-p", str(p)],
                                     capture_output=True, text=True,
                                     timeout=30).stdout
            except Exception:
                continue
            for line in out.splitlines():
                if "NEEDED" not in line and "RUNPATH" not in line \
                        and "RPATH" not in line:
                    continue
                for m in host_markers:
                    if m in line:
                        bad.append(f"{rel}: {line.strip()}")
        if bad:
            raise BuildError(
                "产物仍链接宿主库，自举未真正完成：\n  "
                + "\n  ".join(bad[:10]))
        self._log(f"[自检] {len(relpaths)} 个产物未链接宿主库")

    def default_package(self):
        """配方没写 package() 时的默认行为：按常见前缀搬文件。"""
        raise util.die if False else RuntimeError(
            "配方未定义 package()，也没有可推断的安装方式")

    def rm(self, *patterns):
        """从 destdir 删除不需要的构建残留（静态库、文档等）。"""
        import glob
        for p in patterns:
            for m in glob.glob(str(self.destdir / p), recursive=True):
                if os.path.isdir(m) and not os.path.islink(m):
                    shutil.rmtree(m, ignore_errors=True)
                else:
                    os.unlink(m)


class Builder:
    def __init__(self, root: Path, arch: str = util.ARCH, jobs: int | None = None,
                 sign_key: Path | None = None, verbose: bool = True,
                 repo_dir: Path | None = None, pubkey: Path | None = None,
                 target_arch: str | None = None):
        self.root = Path(root)
        self.arch = arch
        # target_arch 与 arch 不同就是交叉编译。交叉时 arch 仍是构建机
        # （工具链和中间产物属于构建机），target_arch 是产物架构。
        self.target_arch = target_arch or arch
        self.cross = None
        if self.target_arch != arch:
            from . import crosstool as CT
            self.cross = CT.Triple(build=arch, host=self.target_arch)
        self.sign_key = Path(sign_key) if sign_key else None
        self.verbose = verbose
        self.paths = {k: self.root / v for k, v in DEFAULT_LAYOUT.items()}
        for p in self.paths.values():
            p.mkdir(parents=True, exist_ok=True)
        self.sandbox = sandboxmod.Sandbox(jobs=jobs)
        self.recipes = recipemod.load_tree(self.root / "recipes")
        from . import patch as PM
        self.patches = PM.load_patches(self.root, self.root / "recipes")
        # 构建依赖的安装根（自举前指向 sysroot，自举后就是自建系统）
        self.sysroot = self.root / "var" / "sysroot"
        self.repo_dir = Path(repo_dir) if repo_dir else self.root / "var" / "repo"
        self.pubkey = Path(pubkey) if pubkey else None

    def log(self, msg: str) -> None:
        if self.verbose:
            util.log("info", f"    $ {msg}")

    # -- 路径 ------------------------------------------------------

    def pkg_path(self, rec) -> Path:
        return self.paths["pkgs"] / rec.filename

    def _drop_older(self, rec) -> None:
        """产出新版后删掉同名旧包。

        留着旧包会让仓库和审计工具分不清哪个是当前版本。
        """
        prefix = f"{rec.name}-"
        for p in self.paths["pkgs"].glob(f"{prefix}*.qyp"):
            if p.name == rec.filename:
                continue
            try:
                m = fmt.read_package(p).meta
            except Exception:
                p.unlink(missing_ok=True)
                continue
            if m.name == rec.name and m.pkgid != rec.pkgid:
                p.unlink(missing_ok=True)
                util.log("info", f"移除旧版本产物 {p.name}")

    def is_built(self, rec) -> bool:
        p = self.pkg_path(rec)
        if not p.exists():
            return False
        try:
            return fmt.read_package(p).verify()
        except Exception:
            return False

    # -- 单包构建 --------------------------------------------------

    def build(self, name: str, force: bool = False, keep: bool = False) -> Path:
        rec = self.recipes.get(name)
        if rec is None:
            util.die(f"配方树里没有包: {name}")
        self.check_buildable(rec)
        target = self.pkg_path(rec)
        if not force and self.is_built(rec):
            util.log("info", f"{rec.pkgid} 已是最新，跳过（--force 可重编）")
            return target

        util.log("ok", f"构建 {rec.pkgid} [{self.sandbox.describe()}]")
        work = self.paths["work"] / rec.name
        srcdir = work / "src"
        builddir = work / "build"
        destdir = work / "dest"
        for d in (srcdir, builddir, destdir):
            if d.exists():
                shutil.rmtree(d)
            d.mkdir(parents=True)

        ctx = BuildContext(rec, {"srcdir": srcdir, "builddir": builddir,
                                 "destdir": destdir,
                                 "pkgdir": self.paths["pkgs"],
                                 "sysroot_path": self.sysroot},
                           self.sandbox, self.log, cross=self.cross)
        ctx.sysroot = self.sysroot

        t0 = util.timer()
        try:
            self._fetch(rec, srcdir)
            self._apply_patches(rec, srcdir)
            self._prepare_sysroot(rec, ctx)
            self._build_phase(rec, ctx)
            self._package_phase(rec, ctx)
            self._pack(rec, destdir, target)
            if self.cross is not None:
                self._check_arch(rec, target)
        except Exception as e:
            util.log("err", f"{rec.name} 构建失败: {e}")
            self._cross_hint(e)
            if self.verbose:
                traceback.print_exc()
            sys.exit(1)
        finally:
            if not keep:
                shutil.rmtree(builddir, ignore_errors=True)
                shutil.rmtree(destdir, ignore_errors=True)

        dt = util.timer() - t0
        size = target.stat().st_size if target.exists() else 0
        self._drop_older(rec)
        util.log("ok", f"{rec.pkgid} 完成 ({util.fmt_duration(dt)}, "
                       f"{util.human_size(size)}) -> {target.relative_to(self.root)}")
        return target

    def _fetch(self, rec, srcdir: Path) -> None:
        if not rec.source:
            util.log("info", "无外部源码（本地/元包）")
            return
        cache = self.paths["src"]
        for i, url in enumerate(rec.source):
            want = rec.sha256[i] if i < len(rec.sha256) else None
            if url.startswith(("http://", "https://", "ftp://")):
                local = util.fetch(url, cache, want)
                util.unpack(local, srcdir, strip=rec.strip_components
                            if len(rec.source) == 1 else 0)
            else:
                local = (self.root / url).resolve()
                if not local.exists():
                    util.die(f"本地源码不存在: {local}")
                if local.is_dir():
                    # 本地源码目录：直接拷贝，便于离线开发与自测
                    util.log("info", f"使用本地源码目录 {local.name}")
                    for item in local.iterdir():
                        dst = srcdir / item.name
                        if item.is_dir():
                            shutil.copytree(item, dst, symlinks=True)
                        else:
                            shutil.copy2(item, dst)
                else:
                    util.unpack(local, srcdir, strip=rec.strip_components
                                if len(rec.source) == 1 else 0)

    def _apply_patches(self, rec, srcdir: Path) -> None:
        """解包后打补丁。

        有补丁就打，打不上直接失败——静默跳过的后果是
        "以为修了其实没修"，比构建失败危险得多。
        """
        from . import patch as PM
        lst = self.patches.get(rec.name)
        if not lst:
            return
        util.log("info", f"{rec.name}: {len(lst)} 个补丁")
        applied = PM.apply_patches(self.root, rec.name,
                                   srcdir.resolve(), lst)
        # 打过的补丁写进元数据，用户能查到这个包和上游差在哪
        rec.applied_patches = [
            {"file": a.file, "kind": a.kind,
             "reason": a.reason, "cve": a.cve,
             "upstream_commit": a.upstream_commit}
            for a in applied]

    def _prepare_sysroot(self, rec, ctx: BuildContext) -> None:
        """把 makedepends 装进 sysroot，并把头文件和库路径注入构建环境。

        自举之前 sysroot 只装自建包；自举之后可以指向自建系统本身。
        这一步是后面做交叉编译（host 与 target 分离）的接口。
        """
        if not rec.makedepends:
            return
        from . import pkgmgr as PM
        from . import repo as R
        idx_path = self.repo_dir / self.arch / "index.json"
        if not idx_path.exists():
            util.log("warn", f"{rec.name} 需要构建依赖 {rec.makedepends}，"
                             f"但仓库还没有索引，先自行构建这些包")
            return
        pub = self.pubkey
        if pub is None:
            cand = self.repo_dir / "keys" / "qiyuan.pub"
            pub = cand if cand.exists() else None
        mgr = PM.Manager(self.sysroot, self.repo_dir, pub, allow_unsigned=True)
        installed = mgr.db.installed()

        # 尚未构建出来的重包（gcc / glibc 之类）由宿主提供。
        # 这正是自举第一关的真实状态：早期包只能用宿主的编译器和 libc。
        # 不把它们剔除的话，依赖求解会直接报"找不到包"而卡死整个构建。
        host_provided, missing = [], []
        for d in rec.makedepends:
            if d in installed:
                continue
            if self._is_unbuilt_heavy(d, mgr):
                host_provided.append(d)
            else:
                missing.append(d)

        if host_provided:
            util.log("info", f"{rec.name}: {' '.join(host_provided)} "
                             f"尚未自举，暂由宿主提供")
        if missing:
            util.log("step", f"安装构建依赖到 sysroot: {' '.join(missing)}")
            mgr.install(missing, as_explicit=False)
            # libtool .la 内 libdir=/usr/lib 会让链接期去宿主找依赖库；
        # 重写为 sysroot 实际路径，保证自包含
        import re as _re
        import os as _os
        # 用 os.walk 替代 rglob：跳过挂载的 /proc，避免扫描 map_files 触发权限拒绝
        for _dp, _dns, _fns in _os.walk(self.sysroot):
            if _dp == str(self.sysroot) and "proc" in _dns:
                _dns.remove("proc")
            for _fn in _fns:
                if not _fn.endswith(".la"):
                    continue
                la = Path(_dp) / _fn
                try:
                    txt = la.read_text()
                    new = txt.replace("='/usr/lib/", f"='{self.sysroot}/usr/lib/")
                    new = new.replace(" '/usr/lib/", f" {self.sysroot}/usr/lib/").replace(" /usr/lib/lib", f" {self.sysroot}/usr/lib/lib")
                    if new != txt:
                        la.write_text(new)
                except Exception:
                    pass


        inc = self.sysroot / "usr" / "include"
        lib = self.sysroot / "usr" / "lib"
        if inc.exists():
            ctx.env("CPATH", f"{inc}")
            ctx.env("CFLAGS", f"{sandboxmod.BASE_CFLAGS} -I{inc}")
            ctx.env("CXXFLAGS", f"{sandboxmod.BASE_CXXFLAGS} -I{inc}")
        # gobject-introspection 的 giscanner 模块装入 sysroot 后，
        # 构建期工具必须能 import 到它，否则所有带 introspection 的包全挂
        import platform as _pf3
        gi_pp = self.sysroot / "usr" / "lib" / f"{_pf3.machine()}-linux-gnu" / "gobject-introspection"
        if gi_pp.exists():
            ctx.env("PYTHONPATH", f"{gi_pp}")
            # PATH 禁止全局注入：sysroot gcc 排前位会混宿主 libc 头，
            # 把宿主 gcc 的 configure 全炸成 "C compiler cannot create executables"。
            # glib 等需要 sysroot 工具的配方自己在命令里加 export PATH 前缀。
        if lib.exists():
            import platform as _pf2
            libroot = self.sysroot / "lib"
            mlib = lib / (_pf2.machine() + "-linux-gnu")
            rl = ":".join(str(p) for p in (lib, libroot, mlib) if p.exists())
            ctx.env("LIBRARY_PATH", ":".join(str(p) for p in (lib, libroot, mlib) if p.exists()))
            ctx.env("LDFLAGS", f"{sandboxmod.BASE_LDFLAGS} -L{lib} -Wl,-rpath-link,{rl}")
            # 构建期工具（as/ld 等）动态链 sysroot libbfd：不能靠全局
            # LD_LIBRARY_PATH 解决——宿主 bash/gawk/grep 会先撞上 sysroot 的
            # libreadline/libtinfo（"undefined symbol: UP"→config.status 崩，
            # Makefile 创建失败）。binutils 工具已用 patchelf --set-rpath
            # /usr/lib 自带搜索路径（binutils.py 打包时也应写入 RUNPATH）。
        # pkgconfig 注入必须独立于 usr/lib 是否存在（见 _inject_pkgconfig 文档）。
        self._inject_pkgconfig(ctx)

    def _inject_pkgconfig(self, ctx: BuildContext) -> None:
        """把 sysroot 里所有 pkgconfig 目录注入 PKG_CONFIG_PATH。

        必须独立于 `usr/lib` 是否存在：X11 协议类包（xorgproto/xtrans 等）
        只装 `.pc` 到 `usr/share/pkgconfig`，此时 sysroot 里根本没有 `usr/lib`，
        若把这段逻辑挂在 `if lib.exists()` 里，libXau 这类包的 configure 就会
        报 `Package requirements (xproto) were not met` —— 实际 .pc 就在 sysroot 里。
        """
        import platform as _pf
        lib = self.sysroot / "usr" / "lib"
        cands = [
            lib / "pkgconfig",
            lib / (_pf.machine() + "-linux-gnu") / "pkgconfig",
            lib / "pkgconfig" / "..",  # 占位保持顺序稳定
            self.sysroot / "usr" / "share" / "pkgconfig",
            self.sysroot / "lib" / "pkgconfig",
        ]
        paths = [str(p) for p in cands if p.is_dir()]
        if paths:
            existing = ctx.env_extra.get("PKG_CONFIG_PATH")
            joined = ":".join(paths + ([existing] if existing else []))
            ctx.env("PKG_CONFIG_PATH", joined)
            ctx.env("PKG_CONFIG_SYSROOT_DIR", f"{self.sysroot}")

    def _build_phase(self, rec, ctx: BuildContext) -> None:
        util.log("step", "构建阶段")
        rec.build_fn(ctx)

    def _package_phase(self, rec, ctx: BuildContext) -> None:
        util.log("step", "打包阶段（产物只进 destdir）")
        ctx.destdir.mkdir(parents=True, exist_ok=True)
        rec.package_fn(ctx)
        if not any(ctx.destdir.iterdir()):
            util.die(f"{rec.name} 的 destdir 为空，package() 没有产出任何文件")

    def _cross_hint(self, err) -> None:
        """交叉编译时把含糊的失败翻译成可行动的诊断。

        工具链没装好的表现是 gcc: command not found 或 make 非零退出，
        看不出缺的是交叉工具链。不翻译的话，维护者会怀疑是配方写错了，
        而配方一点问题没有。
        """
        if self.cross is None:
            return
        from . import crosstool as CT
        missing = CT.check_toolchain(self.target_arch)
        if not missing:
            return
        util.log("warn",
                 f"交叉工具链缺失 {len(missing)} 个工具，"
                 f"例如 {missing[0]}")
        util.log("info",
                 f"先编出交叉工具链：qybuild --target-arch "
                 f"{self.target_arch} binutils gcc")
        util.log("info",
                 f"或用系统已有的：apt install gcc-"
                 f"{'aarch64' if 'aarch64' in self.target_arch else 'x86-64'}"
                 f"-linux-gnu")

    def _check_arch(self, rec, pkg_path: Path) -> None:
        """交叉编译后校验产物架构。

        最容易出的错是"编出来还是 x86_64 却当成 aarch64 发出去"。
        装上设备报"格式错误"，而构建日志看起来一切正常——
        不在这里查，问题要等到装机才暴露。
        """
        from . import crosstool as CT
        problems = CT.scan_pkg_arch(pkg_path, self.target_arch)
        if problems:
            raise BuildError(
                f"{rec.name} 产物不是 {self.target_arch} 架构：\n  "
                + "\n  ".join(problems[:5])
                + f"\n  检查交叉工具链是否就绪：which "
                  f"{CT.tool_prefix(self.target_arch)}gcc")
        self.log(f"[自检] 产物架构为 {self.target_arch}")

    def _pack(self, rec, destdir: Path, target: Path) -> None:
        # 自动依赖发现：扫产物实际链接了哪些库，补进 depends。
        # 手工维护依赖必然遗漏（忘写 glibc 是最常见的），后果是装包时
        # 依赖没被拉进来、程序启动就报找不到共享库，且安全扫描会漏。
        depends = list(rec.depends)
        if rec.options and "!shlibdeps" in rec.options:
            pass                      # 维护者显式关掉了自动发现
        else:
            try:
                from . import shlibdeps as SD
                from .deps import Universe
                u = Universe()
                for r in self.recipes.values():
                    u.add(r)
                avail = {e.get("name") for e in self._repo_index().get("packages", [])}
                scan = SD.scan_package(destdir, rec, u, available=avail)
                added = [d for d in scan.auto_deps if d not in depends]
                if added:
                    depends.extend(added)
                    util.log("info", f"{rec.name}: 自动补上依赖 "
                                     f"{' '.join(added)}（由产物链接的库反查）")
                if scan.host_provided:
                    util.log("info", f"{rec.name}: "
                                     f"{' '.join(sorted(set(scan.host_provided.values())))}"
                                     f" 尚未自举，暂由宿主提供")
                if scan.unresolved:
                    util.log("warn", f"{rec.name}: 有 {len(scan.unresolved)} 个"
                                     f"库未找到提供者: "
                                     f"{' '.join(scan.unresolved[:5])}")
            except Exception as e:
                # 自动分析失败不该让构建挂掉——它只是增强，
                # 手工声明的依赖仍然生效。但要说清楚。
                util.log("warn", f"{rec.name}: 自动依赖分析失败（{e}），"
                                 f"仅使用配方声明的依赖")

        meta = fmt.Meta(
            name=rec.name, version=rec.version, release=rec.release,
            arch=self.arch, summary=rec.summary, description=rec.description,
            homepage=rec.homepage, license=rec.license,
            depends=depends, makedepends=list(rec.makedepends),
            provides=list(rec.provides), conflicts=list(rec.conflicts),
            replaces=list(rec.replaces),
            scripts=dict(getattr(rec, "scripts", {}) or {}),
            triggers=list(rec.triggers),
            sysusers=list(rec.sysusers),
            alternatives=list(rec.alternatives),
            # 打了哪些补丁必须记进包里：用户和系统管理员需要能查到
            # "这个包和上游有什么区别"，否则只能猜。
            patches=getattr(rec, "applied_patches", []),
            build={"recipe_sha256": util.sha256_file(rec.path),
                   "sandbox": self.sandbox.describe(),
                   "host": util.ARCH})
        fmt.build_package(meta, destdir, target,
                          priv_path=self.sign_key, comp=rec.compression,
                          config_files=list(rec.config_files))
        pkg = fmt.read_package(target)
        if not pkg.verify():
            util.die(f"{target} 自检失败")

    # -- 批量 ------------------------------------------------------

    def _cycle_plan(self):
        """算出环打破方案（带缓存）。包库大了以后每次重算很浪费。"""
        if not hasattr(self, "_cp"):
            from . import cycles as CY
            try:
                self._cp = CY.plan(self.recipes)
            except Exception as e:
                util.log("warn", f"环分析失败（{e}），按原样构建")
                self._cp = CY.CyclePlan()
            if self._cp.rebuild_pass2:
                util.log("warn", f"存在循环依赖，首轮 "
                                 f"{' '.join(self._cp.rebuild_pass2)} 是"
                                 f"功能不全的断开版，第二轮必须重编")
        return self._cp

    def _repo_index(self) -> dict:
        """读当前仓库索引（用于判断哪些包已经自举出来）。"""
        idx_path = self.repo_dir / self.arch / "index.json"
        if not idx_path.exists():
            return {}
        try:
            return json.loads(idx_path.read_text())
        except (json.JSONDecodeError, OSError):
            return {}

    def publish(self) -> None:
        """把已构建的包同步进仓库并重建索引，供后续包的构建依赖使用。"""
        from . import repo as R
        pkgs = sorted(self.paths["pkgs"].glob("*.qyp"))
        if not pkgs:
            return
        R.add_packages(self.repo_dir, [str(p) for p in pkgs], arch=self.arch)
        index = R.build_index(self.repo_dir, self.arch)
        R.write_index(self.repo_dir, index, self.arch, self.sign_key)
        util.log("info", f"仓库已更新: {index['count']} 个包")

    def check_buildable(self, rec) -> None:
        """构建前置门禁：远程源码没锁定校验和就拒绝构建。

        静默接受未校验的远程源码等于给供应链攻击敞开大门，这里绝不退让。
        """
        # 上游地址都还没填的配方不纳入构建。
        # 与 checksum_pending 同一原则：系统里不能有一个
        # 谁也说不清从哪来的包。这类配方只在依赖图里占位，
        # 让上层形态能算得出闭包
        if getattr(rec, "source_pending", False):
            raise BuildPending(
                f"{rec.name}: 上游源码地址尚未填回，不纳入构建。\n"
                f"  请补上 source / sha256 与 build() / package()，"
                f"再去掉 source_pending = True")
        if not getattr(rec, "checksum_pending", False):
            return
        remote = [s for s in (rec.source or [])
                  if s.startswith(("http://", "https://", "ftp://"))]
        if remote and not rec.sha256:
            raise BuildError(
                f"{rec.name}: 远程源码缺少 sha256，拒绝构建。\n"
                f"  请在能联网的构建机上执行：\n"
                f"    qybuild --fetch-checksums {rec.name}\n"
                f"  该命令会下载源码、算出校验和并写回配方。")

    def _is_unbuilt_heavy(self, name: str, mgr=None) -> bool:
        """判断一个包是不是"需要真实构建机、且还没编出来"的重包。

        这类包在开发阶段由宿主提供（自举第一关的真实状态）。
        """
        rec = self.recipes.get(name)
        if rec is None or not getattr(rec, "requires_build_machine", False):
            return False
        if self.pkg_path(rec).exists():
            return False          # 已经编出来了，不算
        return True

    def _filter_heavy(self, order: list) -> list:
        """把需要真实构建机的包从构建序列里剔除。

        必须在依赖求解**之后**再过滤一次：只在入口处过滤没用，
        求解器会顺着 depends 把它们重新拉回来（glibc 就是典型例子）。
        过滤两次才真正生效。
        """
        if not getattr(self, "skip_heavy", False):
            return order
        kept, skipped = [], []
        for n in order:
            if getattr(self.recipes.get(n), "requires_build_machine", False):
                skipped.append(n)
            else:
                kept.append(n)
        for n in skipped:
            util.log("info", f"跳过 {n}（需真实构建机，"
                             f"加 --include-bootstrap 才会构建）")
        return kept

    def build_many(self, names: list, force: bool = False, keep: bool = False) -> list:
        from .deps import Universe
        u = Universe(broken=self._cycle_plan().broken_deps)
        for r in self.recipes.values():
            u.add(r)
        order = u.resolve(names)
        order = self._filter_heavy(order)
        if not order:
            util.log("warn", "没有可构建的包")
            return []
        util.log("info", f"构建顺序: {' -> '.join(order)}")
        built = []
        pending: list = []
        failed: list = []
        for n in order:
            try:
                built.append(self.build(n, force=force, keep=keep))
            except BuildPending as e:
                # "还没写"不是失败。跳过并记下来，最后一次性列出，
                # 免得刷屏淹没真正的失败
                pending.append(n)
                continue
            except BuildError as e:
                failed.append((n, str(e).splitlines()[0]))
                util.log("err", f"{n} 构建失败: {e}")
                break
            self.publish()   # 边构建边入库，后面的包才能拿到依赖
        if pending:
            util.log("warn",
                     f"{len(pending)} 个配方尚未填回上游源码，已跳过："
                     f"{'、'.join(pending[:6])}"
                     f"{'…' if len(pending) > 6 else ''}")
            util.log("info", "这些只在依赖图里占位，"
                             "补上 source/sha256 与 build()/package() 后纳入构建")
        if failed:
            raise BuildError(f"构建中断于 {failed[-1][0]}")
        return built

    def build_all(self, force: bool = False, keep: bool = False,
                  include_bootstrap: bool = False) -> list:
        """全量构建。默认跳过需要真实构建机的工具链大包。

        gcc/glibc 这类包单次要几十分钟到数小时、数十 GB 磁盘，
        在开发机上跑 `qybuild all` 时不该被静默带进去。
        """
        self.skip_heavy = not include_bootstrap
        names = list(self.recipes)
        return self.build_many(names, force=force, keep=keep)
