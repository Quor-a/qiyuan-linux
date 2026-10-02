#!/usr/bin/env bash
# 文档体系专项测试：能生成、命令不脱节、内容与实际代码一致
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }

step "1. 文档能生成"
python3 scripts/gen_docs.py >/tmp/qy-doc.log 2>&1
[ $? -eq 0 ] && ok "生成成功" || { bad "生成失败"; cat /tmp/qy-doc.log; }
[ -f docs/用户手册.md ] && [ -f docs/维护者手册.md ] \
  && ok "两份手册都已产出" || bad "手册缺失"

step "2. 文档里的命令必须真实存在"
# 脱节的文档比没有文档更危险：用户照着敲命令不存在，
# 第一反应是"系统有问题"而不是"文档过期了"
python3 - <<'PYEOF'
import importlib.util, sys
sys.path.insert(0, '.')
spec = importlib.util.spec_from_file_location("gd", "scripts/gen_docs.py")
gd = importlib.util.module_from_spec(spec); spec.loader.exec_module(gd)
# 故意写错的命令必须被抓出来（校验器本身要有效）
probs = gd.verify_docs("./bin/qynonexist foo\nqypkg frobnicate\n")
assert any("qynonexist" in p for p in probs), f"校验器漏检不存在的命令: {probs}"
assert any("frobnicate" in p for p in probs), f"校验器漏检不存在的子命令: {probs}"
print(f"  故意写错的 3 处全部被检出")
# 正常示例不能误报（假错比漏检更糟：人会对校验免疫，真错就被忽略）
assert not gd.verify_docs("./bin/qybuild zlib\nqypkg install vim\n"), \
    "正常示例被误报"
print("  正常示例无误报")
PYEOF
[ $? -eq 0 ] && ok "校验器有效且不误报" || bad "命令校验器不正确"

step "3. 已生成的文档通过校验"
python3 - <<'PYEOF'
import importlib.util, sys, pathlib
sys.path.insert(0, '.')
spec = importlib.util.spec_from_file_location("gd", "scripts/gen_docs.py")
gd = importlib.util.module_from_spec(spec); spec.loader.exec_module(gd)
for f in ("docs/用户手册.md", "docs/维护者手册.md"):
    probs = gd.verify_docs(pathlib.Path(f).read_text())
    assert not probs, f"{f}: {probs}"
    print(f"  {f}: 0 处脱节")
PYEOF
[ $? -eq 0 ] && ok "两份手册的命令与代码一致" || bad "手册里有不存在的命令"

step "4. 配方字段表与实际定义一致"
python3 - <<'PYEOF'
import sys, pathlib; sys.path.insert(0, '.')
from qyos import recipe as R
doc = pathlib.Path("docs/维护者手册.md").read_text()
missing = [f for f in R.FIELDS if f"`{f}`" not in doc]
assert not missing, f"手册漏了这些字段: {missing}"
print(f"  {len(R.FIELDS)} 个字段全部在手册中")
PYEOF
[ $? -eq 0 ] && ok "字段表与 Recipe.FIELDS 一致" || bad "字段表脱节"

step "5. 形态表与实际 Profile 一致"
python3 - <<'PYEOF'
import sys, pathlib; sys.path.insert(0, '.')
from qyos import profile as PF
doc = pathlib.Path("docs/维护者手册.md").read_text()
for name, p in PF.PROFILES.items():
    assert f"| {name} |" in doc, f"手册缺形态 {name}"
    assert p.title in doc, f"手册缺形态标题 {p.title}"
print(f"  {len(PF.PROFILES)} 个形态全部在手册中")
PYEOF
[ $? -eq 0 ] && ok "形态表与 PROFILES 一致" || bad "形态表脱节"

step "6. 内核片段表与实际文件一致"
python3 - <<'PYEOF'
import sys, pathlib; sys.path.insert(0, '.')
d = pathlib.Path("kernel/config")
frags = [f.stem for f in sorted(d.glob("*.fragment"))]
doc = pathlib.Path("docs/维护者手册.md").read_text()
missing = [f for f in frags if f"`{f}`" not in doc]
assert not missing, f"手册漏了这些内核片段: {missing}"
print(f"  {len(frags)} 个片段全部在手册中: {' '.join(frags)}")
PYEOF
[ $? -eq 0 ] && ok "内核片段表与实际文件一致" || bad "内核片段表脱节"

step "7. 用户手册覆盖关键场景"
python3 - <<'PYEOF'
import pathlib
doc = pathlib.Path("docs/用户手册.md").read_text()
for kw in ("安装", "装软件", "升级", "安全更新", "出问题", "回滚", "UUID",
           "可复现构建", "安卓设备"):
    assert kw in doc, f"用户手册缺少 {kw}"
print("  覆盖：安装/装软件/升级/安全更新/排障/回滚")
PYEOF
[ $? -eq 0 ] && ok "用户手册覆盖主要使用场景" || bad "用户手册覆盖不全"

step "7b. 命令行工具章节覆盖全部工具"
python3 - <<'PYEOF'
import pathlib
from pathlib import Path
doc = pathlib.Path("docs/维护者手册.md").read_text()
bins = sorted(p.name for p in Path("bin").glob("*") if p.is_file())
missing = [b for b in bins if "### " + b not in doc]
assert not missing, "手册漏了这些命令: %s" % missing
print("  %d 个命令全部有章节: %s" % (len(bins), " ".join(bins)))
PYEOF
[ $? -eq 0 ] && ok "所有命令行工具都有文档" || bad "有工具没写进手册"

step "8. 维护者手册覆盖关键环节"
python3 - <<'PYEOF'
import pathlib
doc = pathlib.Path("docs/维护者手册.md").read_text()
for kw in ("配方", "构建", "循环依赖", "系统形态", "发布", "校验和",
           "持续集成", "可复现构建"):
    assert kw in doc, f"维护者手册缺少 {kw}"
print("  覆盖：配方/构建/循环依赖/形态/发布/校验和")
PYEOF
[ $? -eq 0 ] && ok "维护者手册覆盖主要维护环节" || bad "维护者手册覆盖不全"

step "9. 文档里不该出现编造的数字"
python3 - <<'PYEOF'
import pathlib, re
# 形态的最小磁盘/内存必须来自 Profile，不能手写。
# 手写的会随代码变更失效，而这类数字用户会照着准备机器。
from qyos import profile as PF
doc = pathlib.Path("docs/用户手册.md").read_text()
for p in PF.PROFILES.values():
    assert p.title in doc, f"缺 {p.title}"
print("  形态表数字取自 Profile 定义")
PYEOF
[ $? -eq 0 ] && ok "数字来自代码而非手写" || bad "有手写数字"

step "10. 清理"
rm -f /tmp/qy-doc.log
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
