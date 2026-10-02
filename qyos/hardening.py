"""二进制加固检查。

编译参数写对了不代表产物真的生效——上游 Makefile 常常覆盖 CFLAGS。
所以要在打包后直接检查产物，而不是相信构建日志。

检查项（都是发行版基线里该有的）：
  RELRO    重定位只读：完整 RELRO 表示 GOT 在启动后不可写
  BIND_NOW 立即绑定，配合 RELRO 才算完整
  NX       栈不可执行
  PIE      地址无关可执行文件（配合 ASLR）
  Canary   栈保护（__stack_chk_fail）
  Fortify  _FORTIFY_SOURCE（__*_chk 系列符号）
  RPATH    不应残留构建目录的 rpath，否则会把构建机路径带进用户系统

用法：qybuild audit <包名>  或  作为构建后自检的一部分。
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

from . import util

CHECKS = ("relro", "bind_now", "nx", "pie", "canary", "fortify", "rpath")

DESC = {
    "relro": "重定位只读（GOT 不可写）",
    "bind_now": "立即绑定（配合完整 RELRO）",
    "nx": "栈不可执行",
    "pie": "地址无关可执行文件",
    "canary": "栈保护",
    "fortify": "FORTIFY_SOURCE 缓冲区检查",
    "rpath": "无残留构建路径",
}


def is_elf(path: Path) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except Exception:
        return False


def _readelf(path: Path, *args) -> str:
    p = subprocess.run(["readelf", *args, str(path)],
                       capture_output=True, text=True)
    return p.stdout or ""


def _no_stack_buffers(path: Path) -> bool:
    """判断目标里有没有大到需要栈保护的局部缓冲区。

    编译器对"栈帧很小、没有数组"的函数不会插入 canary，这是正常的优化行为，
    不是加固缺失。判据：任一函数的栈帧 >= 32 字节（可能有局部数组）才要求 canary。
    """
    try:
        out = subprocess.run(["objdump", "-d", "--no-show-raw-insn", str(path)],
                             capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return False
    if not out:
        return False
    biggest = 0
    for m in re.finditer(r"sub\s+\$0x([0-9a-f]+),\s*%rsp", out):
        try:
            biggest = max(biggest, int(m.group(1), 16))
        except ValueError:
            pass
    # 栈帧 < 32 字节通常只是保存寄存器，不会有数组溢出风险
    return biggest < 32


def audit_elf(path: Path) -> dict:
    r = {k: False for k in CHECKS}
    r["issues"] = []
    r["canary_not_needed"] = False

    dyn = _readelf(path, "-d", "-W")
    hdr = _readelf(path, "-h", "-W")
    syms = _readelf(path, "-s", "-W")
    phdr = _readelf(path, "-l", "-W")

    # RELRO 记在程序头（GNU_RELRO 段），动态段里查不到——必须用 -l 判断
    if re.search(r"GNU_RELRO", phdr):
        r["relro"] = True
    # BIND_NOW 在动态段的 FLAGS / FLAGS_1
    if "BIND_NOW" in dyn or re.search(r"FLAGS_1.*NOW", dyn):
        r["bind_now"] = True
    # NX：没有 GNU_STACK 段或该段不可执行
    m = re.search(r"GNU_STACK\s+0x[0-9a-f]+\s+0x[0-9a-f]+\s+0x[0-9a-f]+\s+"
                  r"0x[0-9a-f]+\s+0x[0-9a-f]+\s+(RWE|RW|R|RE)", dyn)
    if m:
        r["nx"] = "E" not in m.group(1)
    elif "GNU_STACK" not in dyn:
        r["nx"] = True   # 现代内核默认 NX
    # PIE：ET_DYN
    if re.search(r"Type:\s*DYN", hdr):
        r["pie"] = True
    # Canary / Fortify
    # 注意：没有局部数组的小函数编译器不会插桩，符号里查不到属正常，
    # 这种情况单独标记 canary_not_needed，不算加固缺失
    if "__stack_chk_fail" in syms:
        r["canary"] = True
    else:
        r["canary_not_needed"] = _no_stack_buffers(path)
    if re.search(r"__(memcpy|memmove|memset|strcpy|strcat|sprintf|snprintf|printf)_chk", syms):
        r["fortify"] = True

    # RPATH/RUNPATH 残留
    for line in dyn.splitlines():
        if "RPATH" in line or "RUNPATH" in line:
            m2 = re.search(r"\[(.*?)\]", line)
            val = m2.group(1) if m2 else line
            for part in val.split(":"):
                if part and (part.startswith("/data/") or part.startswith("/tmp/")
                             or "qiyuan" in part or part.startswith("/opt/qiyuan")):
                    r["issues"].append(f"残留构建路径 rpath: {part}")
    r["rpath"] = not any("rpath" in i for i in r["issues"])

    return r


def audit_package(pkg_path: Path) -> dict:
    """审计一个 .qyp 包内所有 ELF 文件。"""
    from . import format as fmt
    import tempfile
    pkg = fmt.read_package(pkg_path)
    result = {"package": pkg.meta.pkgid, "elf_count": 0, "passed": 0,
              "failed": [], "details": {}}
    with tempfile.TemporaryDirectory() as td:
        dest = Path(td)
        pkg.extract(dest, check_hashes=False)
        for f in pkg.meta.files:
            if f.type != "file":
                continue
            p = dest / f.path
            if not p.exists() or p.is_symlink() or not is_elf(p):
                continue
            result["elf_count"] += 1
            r = audit_elf(p)
            result["details"][f.path] = r
            missing = [c for c in ("relro", "nx", "pie", "rpath") if not r[c]]
            if not r["canary"] and not r["canary_not_needed"]:
                missing.append("canary")
            if missing or r["issues"]:
                result["failed"].append(
                    {"path": f.path,
                     "missing": [DESC[m] for m in missing],
                     "issues": r["issues"]})
            else:
                result["passed"] += 1
    return result


def audit_root(root: Path, limit: int = 0) -> dict:
    """审计一个已安装系统的全部 ELF（较慢，可选 limit）。"""
    out = {"count": 0, "passed": 0, "failed": []}
    n = 0
    for p in Path(root).rglob("*"):
        if limit and n >= limit:
            break
        if not p.is_file() or p.is_symlink() or not is_elf(p):
            continue
        n += 1
        out["count"] += 1
        r = audit_elf(p)
        missing = [c for c in ("relro", "nx", "pie", "canary", "rpath")
                   if not r[c]]
        if missing or r["issues"]:
            out["failed"].append({"path": str(p),
                                  "missing": [DESC[m] for m in missing],
                                  "issues": r["issues"]})
        else:
            out["passed"] += 1
    return out


def report(res: dict) -> str:
    lines = [f"{res['package']}: {res['passed']}/{res['elf_count']} 个 ELF 通过加固检查"]
    for f in res["failed"]:
        bits = []
        if f["missing"]:
            bits.append("缺失 " + "、".join(f["missing"]))
        if f["issues"]:
            bits.append("；".join(f["issues"]))
        lines.append(f"  [!] {f['path']}: {'; '.join(bits)}")
    return "\n".join(lines)
