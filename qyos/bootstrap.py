"""自举（bootstrap）分析与闭环检查。

自举 = 用这套系统重建这套系统。它是"原创发行版"和"套壳改版"的分界线：
如果你的系统不能自己编译出自己，那它本质上还是别人的系统。

自举分三关（也就是三个"鸡生蛋"问题）：

  第一关  工具链关：用宿主编译器编出自己的编译器（gcc 第一遍）
  第二关  系统关：用第一遍的工具链编出全套基础系统（不依赖宿主任何库）
  第三关  自持关：用第二遍编出的系统，重新编译所有包，产出的包与
          第二遍的逐字节一致（可复现构建），此后系统不再需要宿主

这里做的是**分析与规划**，不是真的跑编译（编译在真实构建机上做）：
  * 计算构建闭包：要编出目标包，总共得先编出哪些包
  * 检测循环构建依赖（自举最大的实际障碍）
  * 按自举阶段给每个包排序，标出每一关的进出条件
  * 生成可执行的自举计划

判断一个包属于哪一关，看它的构建依赖里有没有"还没被自己编出来"的东西。
"""
from __future__ import annotations

import json
from pathlib import Path

from . import recipe as recipemod
from . import util
from .deps import Universe, DepError

# 自举阶段
STAGE_HOST = 0      # 用宿主工具链
STAGE_PASS1 = 1     # 第一遍：自己的工具链，仍链接宿主库
STAGE_PASS2 = 2     # 第二遍：完全不依赖宿主
STAGE_SELFHOST = 3  # 自持：可复现重建自己

STAGE_NAMES = {
    STAGE_HOST: "宿主",
    STAGE_PASS1: "第一遍",
    STAGE_PASS2: "第二遍",
    STAGE_SELFHOST: "自持",
}

# 工具链核心包：这些包必须先编出来，别的包才有着落
TOOLCHAIN_CORE = ["binutils", "gcc", "glibc", "linux-headers"]


class BootstrapError(RuntimeError):
    pass


def build_closure(recipes: dict, targets: list) -> list:
    """计算构建闭包：要编出 targets，必须先编出哪些包（含自身）。

    这是自举的第一件事——不知道闭包，就无法回答"到底要编多少东西"。
    """
    seen: set = set()
    order: list = []

    def visit(name: str, stack: list) -> None:
        if name in seen:
            return
        if name in stack:
            # 构建依赖成环：A 的构建依赖 B，B 的构建依赖 A
            cyc = " -> ".join(stack[stack.index(name):] + [name])
            raise BootstrapError(f"构建依赖存在循环: {cyc}")
        r = recipes.get(name)
        if r is None:
            return   # 外部依赖（宿主提供），不进闭包
        stack.append(name)
        for d in r.makedepends:
            visit(d, stack)
        stack.pop()
        seen.add(name)
        order.append(name)

    for t in targets:
        visit(t, [])
    return order


def detect_cycles(recipes: dict) -> list:
    """找出所有构建依赖环。环不解决，自举就卡死。"""
    cycles = []
    color: dict = {}      # 0 未访问 1 在栈上 2 已完成
    stack: list = []

    def dfs(n: str) -> None:
        color[n] = 1
        stack.append(n)
        r = recipes.get(n)
        for d in (r.makedepends if r else []):
            if d not in recipes:
                continue
            if color.get(d, 0) == 1:
                cycles.append(stack[stack.index(d):] + [d])
            elif color.get(d, 0) == 0:
                dfs(d)
        stack.pop()
        color[n] = 2

    for n in recipes:
        if color.get(n, 0) == 0:
            dfs(n)
    return cycles


def assign_stages(recipes: dict, order: list, have_host: set) -> dict:
    """给闭包里的每个包判定自举阶段。

    规则：一个包的阶段 = max(它所有构建依赖的阶段) + 约束
      * 依赖宿主才有的东西 → 只能留在宿主阶段（说明还没自举成功）
      * 工具链核心包：第一遍用宿主编，第二遍用第一遍的自己编
      * 其余包：依赖齐了就进下一关
    """
    stage: dict = {}
    for name in order:
        r = recipes.get(name)
        if r is None:
            continue
        deps = [d for d in r.makedepends]
        # 有构建依赖不在配方库里，且不在宿主提供的清单里 → 断链
        unresolved = [d for d in deps
                      if d not in recipes and d not in have_host]
        if unresolved:
            # 断链的包只能等宿主提供，先挂在宿主阶段并标记
            stage[name] = STAGE_HOST
            continue
        dep_stage = max((stage.get(d, STAGE_HOST) for d in deps if d in stage),
                        default=STAGE_HOST)
        if name in TOOLCHAIN_CORE:
            # 工具链在自己的阶段里要编两遍
            stage[name] = STAGE_PASS1 if dep_stage == STAGE_HOST else STAGE_PASS2
        else:
            stage[name] = max(STAGE_PASS1, dep_stage)
    return stage


def selfhost_readiness(recipes: dict, closure: list, stages: dict) -> dict:
    """评估自举就绪度：离"自己编自己"还差什么。"""
    total = len(closure)
    by_stage: dict = {}
    for n in closure:
        by_stage.setdefault(stages.get(n, STAGE_HOST), []).append(n)

    missing = []
    for n in closure:
        r = recipes[n]
        for d in r.makedepends:
            if d not in recipes:
                missing.append({"package": n, "needs": d})

    # 工具链三件套是否齐备——不齐就谈不上自举
    have_core = [c for c in TOOLCHAIN_CORE if c in recipes]
    core_ok = len(have_core) >= 3

    return {
        "total": total,
        "by_stage": {STAGE_NAMES[k]: sorted(v) for k, v in sorted(by_stage.items())},
        "missing_makedepends": missing,
        "toolchain_core_present": have_core,
        "toolchain_ready": core_ok,
        "blockers": _blockers(closure, stages, missing, core_ok),
    }


def _blockers(closure, stages, missing, core_ok) -> list:
    b = []
    if not core_ok:
        b.append("工具链核心包不完整（binutils/gcc/glibc/linux-headers），"
                 "无法开始第一遍自举")
    if missing:
        names = sorted({m["needs"] for m in missing})
        b.append(f"有 {len(missing)} 个构建依赖没有配方: {', '.join(names[:10])}")
    stuck = [n for n in closure if stages.get(n, STAGE_HOST) == STAGE_HOST]
    if stuck and core_ok:
        b.append(f"{len(stuck)} 个包仍停留在宿主阶段，未进入自举")
    return b


def plan(recipes: dict, targets: list | None = None,
         have_host: set | None = None) -> dict:
    """生成完整自举计划。"""
    have_host = have_host or {"gcc", "binutils", "make", "python3", "bash"}
    targets = targets or list(recipes)

    cycles = detect_cycles(recipes)
    if cycles:
        return {"ok": False, "cycles": cycles,
                "blockers": [f"构建依赖成环: {' -> '.join(c)}" for c in cycles]}

    closure = build_closure(recipes, targets)
    stages = assign_stages(recipes, closure, have_host)
    ready = selfhost_readiness(recipes, closure, stages)

    # 按阶段分批，每批内按依赖顺序
    batches = []
    for st in (STAGE_PASS1, STAGE_PASS2, STAGE_SELFHOST):
        pkgs = [n for n in closure if stages.get(n) == st]
        if pkgs:
            batches.append({"stage": st, "name": STAGE_NAMES[st],
                            "packages": pkgs})
    host_pkgs = [n for n in closure if stages.get(n) == STAGE_HOST]

    return {
        "ok": not ready["blockers"],
        "targets": targets,
        "closure": closure,
        "closure_size": len(closure),
        "stages": {n: STAGE_NAMES.get(s, "?") for n, s in stages.items()},
        "batches": batches,
        "host_stage": host_pkgs,
        "readiness": ready,
        "blockers": ready["blockers"],
    }


def render_report(plan: dict) -> str:
    lines = ["# 自举计划", ""]
    if not plan["ok"]:
        lines.append("**当前无法自举**，阻塞项：")
        for b in plan["blockers"]:
            lines.append(f"- {b}")
        lines.append("")
    r = plan["readiness"]
    lines.append(f"构建闭包 {r['total']} 个包 · "
                 f"工具链核心 {len(r['toolchain_core_present'])}/4")
    lines.append("")
    lines.append("## 分阶段批次")
    for b in plan["batches"]:
        lines.append(f"- **{b['name']}**（{len(b['packages'])} 个）："
                     f"{' '.join(b['packages'])}")
    if plan["host_stage"]:
        lines.append(f"- **宿主阶段**（{len(plan['host_stage'])} 个，"
                     f"尚未进入自举）：{' '.join(plan['host_stage'])}")
    if r["missing_makedepends"]:
        lines += ["", "## 缺失的构建依赖"]
        for m in r["missing_makedepends"][:30]:
            lines.append(f"- {m['package']} 需要 {m['needs']}（无配方）")
    lines += ["", "## 三关说明"]
    lines.append("- 第一关（工具链）：用宿主编译器编出自己的 gcc/binutils")
    lines.append("- 第二关（系统）：用第一遍工具链编出全套基础系统，"
                 "产物不得链接宿主任何库")
    lines.append("- 第三关（自持）：用第二遍的系统重新编译所有包，"
                 "产出需与第二遍逐字节一致")
    return "\n".join(lines)
