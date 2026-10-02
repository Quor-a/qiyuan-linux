"""initramfs 构建器。

内核自己不会挂载真正的根——它只挂载一个临时的早期根（initramfs），
由里面的程序去找到真根、切过去（pivot_root）。没有它，系统起不来。

这里生成一个 gzip 压缩的 cpio 归档，内含：
  * 一个静态链接的早期 init（不依赖任何动态库——此时 /lib 还不存在）
  * 挂载真根所需的目录与设备节点
  * 把"根在哪"写死进去（内核命令行或内嵌配置）

为什么早期 init 必须静态链接：它运行时 /usr/lib 还没挂载，
动态链接器找不到 libc，一执行就段错误。这是新手最容易踩的坑。
"""
from __future__ import annotations

import io
import os
import shutil
import stat
import subprocess
import tarfile
import tempfile
from pathlib import Path

from . import util

# initramfs 里必须有的目录
INITRAMFS_DIRS = ["bin", "dev", "etc", "lib", "mnt", "proc", "root",
                  "run", "sbin", "sys", "newroot"]

# 早期环境需要的设备节点
EARLY_DEVICES = [
    ("dev/console", "c", 5, 1, 0o600),
    ("dev/null", "c", 1, 3, 0o666),
    ("dev/zero", "c", 1, 5, 0o666),
    ("dev/tty", "c", 5, 0, 0o666),
    ("dev/urandom", "c", 1, 9, 0o666),
    ("dev/kmsg", "c", 1, 11, 0o644),
]

EARLY_INIT_C = r'''
/* 早期 init —— 在 initramfs 里运行，负责挂载真根并切过去。
 *
 * 必须静态链接：此时 /usr/lib 还没挂载，动态链接器找不到 libc。
 *
 * 流程：解析 root= → 挂载真根 → 挂载并移动虚拟文件系统 → pivot_root → 交棒真 init
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef ROOT_DEFAULT
#define ROOT_DEFAULT ""
#endif

static void die(const char *msg)
{
    fprintf(stderr, "[early-init] 致命错误: %s: %s\n", msg, strerror(errno));
    fprintf(stderr, "[early-init] 系统无法启动，进入救援 shell\n");
    execl("/bin/sh", "/bin/sh", (char *)NULL);
    _exit(1);
}

/* 从内核命令行取 key=value */
static int cmdline_get(const char *key, char *out, size_t n)
{
    static char buf[4096];
    static int loaded = 0;
    if (!loaded) {
        FILE *f = fopen("/proc/cmdline", "r");
        if (!f) return 0;
        if (!fgets(buf, sizeof buf, f)) { fclose(f); return 0; }
        fclose(f);
        loaded = 1;
    }
    char *p = buf;
    size_t klen = strlen(key);
    while ((p = strstr(p, key)) != NULL) {
        if (p != buf && p[-1] != ' ') { p += klen; continue; }
        const char *v = p + klen;
        if (*v != '=') { p += klen; continue; }
        v++;
        size_t i = 0;
        while (*v && *v != ' ' && *v != '\n' && i + 1 < n) out[i++] = *v++;
        out[i] = '\0';
        return 1;
    }
    return 0;
}

int main(void)
{
    char root[256] = ROOT_DEFAULT;
    char fstype[32] = "";
    char init[256] = "/sbin/init";

    cmdline_get("root", root, sizeof root);
    cmdline_get("rootfstype", fstype, sizeof fstype);
    cmdline_get("init", init, sizeof init);

    fprintf(stderr, "[early-init] 启动，root=%s fstype=%s\n",
            root[0] ? root : "(未指定)", fstype[0] ? fstype : "(自动探测)");

    /* 早期虚拟文件系统必须先挂，后面读分区信息要用 */
    mkdir("/proc", 0755); mkdir("/sys", 0755);
    mkdir("/dev", 0755);  mkdir("/newroot", 0755);
    mkdir("/run", 0755);
    if (mount("proc", "/proc", "proc", 0, NULL) != 0)
        fprintf(stderr, "[early-init] 挂载 /proc 失败: %s\n", strerror(errno));
    if (mount("sysfs", "/sys", "sysfs", 0, NULL) != 0)
        fprintf(stderr, "[early-init] 挂载 /sys 失败: %s\n", strerror(errno));
    if (mount("devtmpfs", "/dev", "devtmpfs", 0, NULL) != 0)
        fprintf(stderr, "[early-init] 挂载 /dev 失败: %s\n", strerror(errno));

    if (!root[0]) {
        /* 没给 root= 时就地运行 shell，方便救援与测试 */
        fprintf(stderr, "[early-init] 未指定 root=，留在 initramfs 环境\n");
        execl("/bin/sh", "/bin/sh", (char *)NULL);
        die("无法执行 /bin/sh");
    }

    /* 挂载真根。fstype 空着让内核自动探测——比写死更稳 */
    const char *types[] = { fstype[0] ? fstype : NULL, "ext4", "xfs",
                            "btrfs", "f2fs", "vfat", NULL };
    int ok = 0;
    for (int i = 0; types[i]; i++) {
        if (mount(root, "/newroot", types[i], 0, NULL) == 0) {
            fprintf(stderr, "[early-init] 已挂载真根 %s (类型 %s)\n",
                    root, types[i]);
            ok = 1; break;
        }
    }
    if (!ok) die("无法挂载真根");

    /* 虚拟文件系统要跟着搬到新根，否则真 init 起来后 /proc 是空的 */
    struct { const char *src, *dst, *type; } moves[] = {
        {"/dev",  "/newroot/dev",  NULL},
        {"/proc", "/newroot/proc", "proc"},
        {"/sys",  "/newroot/sys",  "sysfs"},
        {"/run",  "/newroot/run",  NULL},
    };
    for (size_t i = 0; i < sizeof moves / sizeof moves[0]; i++) {
        if (mount(moves[i].src, moves[i].dst, moves[i].type, MS_MOVE, NULL) != 0)
            fprintf(stderr, "[early-init] 移动 %s 失败: %s\n",
                    moves[i].src, strerror(errno));
    }

    if (chdir("/newroot") != 0) die("chdir /newroot");
    if (pivot_root(".", "mnt") != 0) {
        /* 某些环境（容器、老内核）不支持 pivot_root，用 chroot 兜底 */
        fprintf(stderr, "[early-init] pivot_root 不可用，退回 chroot\n");
        if (chroot(".") != 0) die("chroot");
        if (chdir("/") != 0) die("chdir /");
    }

    fprintf(stderr, "[early-init] 已切换到真根，交棒给 %s\n", init);
    execl(init, init, (char *)NULL);
    die("无法执行真 init");
    return 1;
}
'''


class InitramfsError(RuntimeError):
    pass


def build_early_init(workdir: Path, root_default: str = "",
                     static: bool = True) -> Path:
    """编译早期 init。默认静态链接——动态链接的早期 init 一定跑不起来。"""
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    src = workdir / "early-init.c"
    bin_path = workdir / "early-init"
    src.write_text(EARLY_INIT_C)

    cmd = ["gcc", "-O2", "-Wall", "-Wextra", "-o", str(bin_path), str(src)]
    if root_default:
        cmd.insert(1, f"-DROOT_DEFAULT=\"{root_default}\"")
    if static:
        cmd.insert(1, "-static")
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        # 没有静态 libc 时退回动态链接，并明确告警
        if static:
            util.log("warn", "静态链接失败，退回动态链接"
                             "（真实装机必须用静态版，否则早期 init 起不来）")
            util.log("warn", p.stderr.strip().splitlines()[-1] if p.stderr else "")
            return build_early_init(workdir, root_default, static=False)
        raise InitramfsError(f"编译早期 init 失败:\n{p.stderr}")
    return bin_path


def is_static(path: Path) -> bool:
    """判断 ELF 是否静态链接。早期 init 必须是。"""
    try:
        out = subprocess.run(["file", "-L", str(path)],
                             capture_output=True, text=True, timeout=20).stdout
        return "statically linked" in out
    except Exception:
        return False


def _cpio_header(name: str, mode: int, size: int, ino: int) -> bytes:
    """手写 newc 格式 cpio 头。不依赖外部 cpio 命令，行为可复现。"""
    def f(v, w):
        return f"{v:0{w}x}".encode()

    fields = [
        b"070701",                    # magic (newc)
        f(ino, 8),                    # ino
        f(mode, 8),                   # mode
        f(0, 8),                      # uid
        f(0, 8),                      # gid
        f(1, 8),                      # nlink
        f(0, 8),                      # mtime（固定，保证可复现）
        f(size, 8),                   # filesize
        f(0, 8), f(0, 8), f(0, 8), f(0, 8),   # devmajor/minor, rdevmajor/minor
        f(len(name) + 1, 8),          # namesize
        f(0, 8),                      # check
    ]
    return b"".join(fields) + name.encode() + b"\0"


def _pad(b: bytes, align: int = 4) -> bytes:
    n = (-len(b)) % align
    return b + b"\0" * n


def write_cpio(out_path: Path, staging: Path, entries: list) -> int:
    """把 staging 里的一批条目打成 cpio(newc) 并 gzip 压缩。

    entries: [(相对路径, 类型)]  类型 ∈ dir/file/symlink/device
    """
    import gzip

    staging = Path(staging)
    buf = io.BytesIO()
    ino = 1

    for rel, kind in entries:
        name = rel
        if kind == "dir":
            buf.write(_pad(_cpio_header(name, stat.S_IFDIR | 0o755, 0, ino), 4))
        elif kind == "symlink":
            target = os.readlink(staging / rel)
            data = target.encode()
            buf.write(_pad(_cpio_header(
                name, stat.S_IFLNK | 0o777, len(data), ino), 4))
            buf.write(_pad(data, 4))
        elif kind == "device":
            st = (staging / rel).stat()
            buf.write(_pad(_cpio_header(
                name, stat.S_IFCHR | (st.st_mode & 0o7777), 0, ino), 4))
        else:  # file
            p = staging / rel
            data = p.read_bytes()
            mode = stat.S_IFREG | (p.stat().st_mode & 0o7777)
            buf.write(_pad(_cpio_header(name, mode, len(data), ino), 4))
            buf.write(_pad(data, 4))
        ino += 1

    # 结束标记：名为 TRAILER!!! 的空文件
    buf.write(_pad(_cpio_header("TRAILER!!!", stat.S_IFREG | 0o644, 0, ino), 4))

    raw = buf.getvalue()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        gz = gzip.GzipFile(filename="", mode="wb", compresslevel=9,
                           fileobj=f, mtime=0)
        gz.write(raw)
        gz.close()
    return len(raw)


def build(root_target: str = "", out_path: Path | None = None,
          workdir: Path | None = None, extra_bins: list | None = None,
          shell: str | None = None) -> dict:
    """构建 initramfs。返回 {path, size, static, entries}。"""
    workdir = Path(workdir) if workdir else Path(tempfile.mkdtemp(prefix="qy-iramfs-"))
    workdir.mkdir(parents=True, exist_ok=True)
    staging = workdir / "staging"
    if staging.exists():
        shutil.rmtree(staging)

    for d in INITRAMFS_DIRS:
        (staging / d).mkdir(parents=True, exist_ok=True)

    # 早期 init：静态链接，装在 /init（内核固定找这个名字）
    early = build_early_init(workdir, root_default=root_target)
    (staging / "init").parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(early, staging / "init")
    os.chmod(staging / "init", 0o755)

    # 静态 shell（救援用）：没有就跳过，但要告警
    sh = None
    for cand in ([shell] if shell else []) + ["/bin/busybox", "/bin/dash.static",
                                              "/bin/sh"]:
        if cand and Path(cand).exists():
            sh = cand
            break
    entries = []

    if sh:
        dst = staging / "bin" / "sh"
        shutil.copy2(sh, dst)
        os.chmod(dst, 0o755)
        entries.append((f"bin/sh", "file"))
        util.log("info", f"纳入救援 shell: {sh}")
    else:
        util.log("warn", "没有找到静态 shell，initramfs 将无法提供救援环境")

    entries.append(("init", "file"))
    for d in INITRAMFS_DIRS:
        entries.append((d, "dir"))

    # 设备节点（有权限才建；没有就把清单写进去，装机时补）
    for path, kind, maj, minr, mode in EARLY_DEVICES:
        p = staging / path
        p.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.mknod(p, stat.S_IFCHR | mode, os.makedev(maj, minr))
            entries.append((path, "device"))
        except (OSError, PermissionError):
            pass

    out = Path(out_path) if out_path else workdir / "initramfs.img"
    raw_size = write_cpio(out, staging, entries)

    static_ok = is_static(early)
    if not static_ok:
        util.log("warn", "早期 init 不是静态链接——真实内核下会无法启动")

    size = out.stat().st_size
    util.log("ok", f"initramfs 已生成 {out} "
                   f"(未压缩 {util.human_size(raw_size)} → "
                   f"{util.human_size(size)}，{len(entries)} 项)")
    return {"path": out, "size": size, "raw_size": raw_size,
            "static": static_ok, "entries": len(entries),
            "root": root_target, "workdir": workdir}


def inspect(path: Path) -> dict:
    """检视一个 initramfs：列出内容、判断是否可启动。

    装机前必查：早期 init 在不在、是不是静态的。这两个任一不满足就是起不来。
    """
    import gzip
    path = Path(path)
    try:
        with gzip.open(path, "rb") as f:
            raw = f.read()
    except Exception as e:
        raise InitramfsError(f"不是有效的 gzip initramfs: {e}")

    items, pos = [], 0
    while True:
        if pos + 110 > len(raw):
            break
        if raw[pos:pos + 6] != b"070701":
            raise InitramfsError(f"偏移 {pos} 处 cpio magic 不对")
        def g(off, n):
            return int(raw[pos + off:pos + off + n], 16)
        mode = g(14, 8)
        size = g(54, 8)
        namesize = g(94, 8)
        name = raw[pos + 110:pos + 109 + namesize].split(b"\0")[0].decode()
        hlen = 110 + namesize
        hlen = (hlen + 3) & ~3
        if name == "TRAILER!!!":
            break
        kind = "file"
        if stat.S_ISDIR(mode):
            kind = "dir"
        elif stat.S_ISLNK(mode):
            kind = "symlink"
        elif stat.S_ISCHR(mode) or stat.S_ISBLK(mode):
            kind = "device"
        items.append({"name": name, "type": kind, "size": size})
        pos += hlen + ((size + 3) & ~3)

    names = {i["name"] for i in items}
    problems = []
    if "init" not in names:
        problems.append("缺少 /init——内核找不到入口，无法启动")
    for d in ("proc", "sys", "dev", "newroot"):
        if d not in names:
            problems.append(f"缺少 /{d}")

    # 检查早期 init 是否静态（解压出来看）
    static_init = None
    try:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "init"
            pos = 0
            while True:
                if pos + 110 > len(raw):
                    break
                def g2(off, n):
                    return int(raw[pos + off:pos + off + n], 16)
                size = g2(54, 8)
                namesize = g2(94, 8)
                name = raw[pos + 110:pos + 109 + namesize].split(b"\0")[0].decode()
                hlen = (110 + namesize + 3) & ~3
                if name == "init":
                    p.write_bytes(raw[pos + hlen:pos + hlen + size])
                    static_init = is_static(p)
                    break
                pos += hlen + ((size + 3) & ~3)
    except Exception:
        pass
    if static_init is False:
        problems.append("/init 不是静态链接——真根挂载前动态库不可用，会段错误")

    return {"items": items, "count": len(items), "problems": problems,
            "bootable": not problems, "static_init": static_init,
            "raw_size": len(raw), "file_size": path.stat().st_size}
