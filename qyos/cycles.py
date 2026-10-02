"""循环依赖处理（环打破）。

这不是理论问题——包库到 166 个时就撞上了一个真实的环：

    cairo → fontconfig → freetype → harfbuzz → cairo

freetype 需要一个能塑形的 harfbuzz，harfbuzz 需要 freetype 取字形，
而它俩都要 cairo，cairo 又要 fontconfig。上游互相依赖，谁也先不了。

所有发行版都得处理这个。LFS 处理 gcc/glibc 用的是同一套思路：
**断开一环，先编出一个功能不全但能用的版本，用它编出其余的，再重编。**

这里实现：
  * 找出所有环（Tarjan 强连通分量），一次性报全，而不是遇到一个崩一个
  * 配方用 cycle_break 声明"这个依赖在首轮先不满足"
  * 求解器按声明断开环，产出可执行的构建顺序
  * 生成两遍计划：先编断开版，环上包齐了再重编那些声明了 cycle_break 的包

关键约束：**必须记录哪些包是"功能不全的断开版"**。忘了重编，
系统会带着一个不支持复杂文本排版的 freetype 发布出去——
能跑、能过测试，中文和阿拉伯文渲染是错的。
"""
from __future__ import annotations

from dataclasses import dataclass, field

from . import util


class CycleError(RuntimeError):
    pass


@dataclass
class CyclePlan:
    """打破环之后的构建计划。"""
    order: list = field(default_factory=list)        # 首轮构建顺序
    cycles: list = field(default_factory=list)       # 发现的环
    broken_deps: dict = field(default_factory=dict)  # 包名 → 被暂时断开的依赖
    rebuild_pass2: list = field(default_factory=list)  # 需要重编的包

    @property
    def has_cycles(self) -> bool:
        return bool(self.cycles)

    def summary(self) -> str:
        lines = []
        if not self.cycles:
            lines.append("未发现循环依赖")
            return "\n".join(lines)
        lines.append(f"发现 {len(self.cycles)} 个循环依赖：")
        for c in self.cycles:
            lines.append(f"  {' → '.join(c)} → 回到 {c[0]}")
        lines.append("")
        lines.append("首轮将暂时断开这些依赖：")
        for pkg, deps in sorted(self.broken_deps.items()):
            lines.append(f"  {pkg} 暂不依赖 {' '.join(deps)}")
        lines.append("")
        lines.append(f"第二轮需重编 {len(self.rebuild_pass2)} 个包（否则它们是功能不全的）：")
        for p in self.rebuild_pass2:
            lines.append(f"  {p}")
        return "\n".join(lines)


def find_cycles(recipes: dict) -> list:
    """找出所有循环依赖。用 Tarjan 强连通分量，一次找全。

    逐个试错的方式（构造到一半才崩）在包库变大后会变成噩梦：
    修好一个环，下一个才暴露，反复几十轮。
    """
    graph = {}
    for n, r in recipes.items():
        deps = list(r.depends or []) + list(r.makedepends or [])
        graph[n] = [d for d in deps if d in recipes and d != n]

    # 自环单独记
    self_loops = [[n] for n, ds in graph.items() if n in ds]

    index, low, on_stack, stack, out = {}, {}, set(), [], []
    counter = [0]

    def strong(v):
        stack.append(v); on_stack.add(v)
        index[v] = low[v] = counter[0]; counter[0] += 1
        for w in graph.get(v, ()):
            if w not in index:
                strong(w)
                low[v] = min(low[v], low[w])
            elif w in on_stack:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop(); on_stack.discard(w); comp.append(w)
                if w == v:
                    break
            out.append(comp)

    for v in graph:
        if v not in index:
            strong(v)

    return [sorted(c) for c in out if len(c) > 1] + self_loops


def plan(recipes: dict) -> CyclePlan:
    """算出打破环之后的构建计划。"""
    cycles = find_cycles(recipes)
    cp = CyclePlan(cycles=cycles)
    if not cycles:
        return cp

    # 收集每个包声明的可断开依赖
    breakable = {}
    for n, r in recipes.items():
        declared = list(getattr(r, "cycle_break", None) or [])
        if declared:
            breakable[n] = set(declared)

    in_cycle = set()
    for c in cycles:
        in_cycle.update(c)

    # 在环内找可以断开的边：优先用配方显式声明的
    broken = set()
    for c in cycles:
        cut = False
        for pkg in c:
            for dep in (breakable.get(pkg) or ()):
                if dep in c:
                    broken.add((pkg, dep))
                    cut = True
                    break
            if cut:
                break
        if not cut:
            raise CycleError(
                f"环 {' → '.join(c)} 无法打破：环上的包都没有用 "
                f"cycle_break 声明可暂时断开的依赖。\n"
                f"  请在上游那一侧的配方里加 "
                f"cycle_break = [\"<环上的某个包>\"]，\n"
                f"  表示先用功能不全的版本编一遍，之后再重编。")

    for pkg, dep in sorted(broken):
        cp.broken_deps.setdefault(pkg, []).append(dep)

    # 需要重编：声明了 cycle_break 且确实被断开过
    for pkg in sorted(in_cycle):
        if pkg in cp.broken_deps and any(
                d in recipes[pkg].depends for d in cp.broken_deps[pkg]):
            cp.rebuild_pass2.append(pkg)
    # 环上真正依赖被断开项的包也要重编（它的输入变全了）
    for pkg in sorted(in_cycle):
        if pkg in cp.rebuild_pass2:
            continue
        declared = breakable.get(pkg) or set()
        if declared and declared & {d for _, d in broken}:
            cp.rebuild_pass2.append(pkg)

    # 用断开后的图做拓扑排序
    graph = {}
    for n, r in recipes.items():
        deps = list(r.depends or []) + list(r.makedepends or [])
        skip = set(cp.broken_deps.get(n, ()))
        graph[n] = [d for d in deps if d in recipes and d != n and d not in skip]

    order, done = [], set()

    def visit(n, stack):
        if n in done:
            return
        if n in stack:
            raise CycleError(f"断开后仍有环: {' → '.join(stack + [n])}")
        for d in graph.get(n, ()):
            visit(d, stack + [n])
        done.add(n)
        order.append(n)

    for n in recipes:
        visit(n, [])

    cp.order = order
    return cp


def apply_break(recipes: dict, cp: CyclePlan) -> dict:
    """返回首轮构建时"生效的依赖关系"（断开版），供求解器使用。"""
    effective = {}
    for n, r in recipes.items():
        skip = set(cp.broken_deps.get(n, ()))
        deps = [d for d in (r.depends or []) if d not in skip]
        effective[n] = deps
    return effective
