#!/usr/bin/env bash
# 交叉编译专项测试：三元组、环境变量、工具链文件、架构校验
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/home/agentuser/qyw/.qy-cross
for _ in 1 2 3; do rm -rf "$TMP" 2>/dev/null; [ -e "$TMP" ] || break; sleep 1; done
mkdir -p "$TMP"

step "1. 架构名归一"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import crosstool as CT
# 同一台机器在不同系统上写法不同，不归一会导致 sysroot 路径对不上
for a, want in (("amd64","x86_64"), ("x86-64","x86_64"), ("x86_64","x86_64"),
                ("arm64","aarch64"), ("aarch64","aarch64")):
    assert CT.normalize_arch(a) == want, f"{a} → {CT.normalize_arch(a)}，应 {want}"
print("  amd64/x86-64 → x86_64；arm64 → aarch64")
try:
    CT.triplet("nonexistent-arch")
    raise AssertionError("未知架构没报错")
except CT.CrossError:
    print("  未知架构 → 明确报错")
PYEOF
[ $? -eq 0 ] && ok "架构名归一且未知架构报错" || bad "架构归一不正确"

step "2. 三种模式识别"
./bin/qycross info > "$TMP/n.txt" 2>&1
grep -q "原生编译" "$TMP/n.txt" && ok "同架构 → 原生编译" || bad "原生未识别"
./bin/qycross info --host aarch64 > "$TMP/c.txt" 2>&1
grep -q "交叉编译" "$TMP/c.txt" && ok "跨架构 → 交叉编译" || bad "交叉未识别"
./bin/qycross info --host x86_64 --target aarch64 > "$TMP/cc.txt" 2>&1
grep -q "加拿大交叉" "$TMP/cc.txt" && ok "三者不同 → 加拿大交叉" || bad "加拿大交叉未识别"

step "3. 三元组含义要说清"
grep -q "编译器在哪跑" "$TMP/c.txt" && grep -q "产物在哪跑" "$TMP/c.txt" \
  && ok "说明了 build 与 host 区别" || bad "未说明三元组含义"

step "4. 交叉环境变量"
./bin/qycross env --host aarch64 --sysroot /opt/root > "$TMP/env.txt" 2>&1
grep -q "^CC=aarch64-qiyuan-linux-gnu-gcc" "$TMP/env.txt" \
  && ok "CC 指向交叉编译器" || bad "CC 不对"
grep -q "^CC_FOR_BUILD=cc" "$TMP/env.txt" \
  && ok "有 CC_FOR_BUILD（构建期程序用宿主编）" || bad "缺 CC_FOR_BUILD"
python3 - <<'PYEOF'
import pathlib, sys
sys.path.insert(0, '.')
from qyos import crosstool as CT
t = CT.Triple(build="x86_64", host="aarch64")
e = CT.CrossEnv(t, sysroot=pathlib.Path("/opt/root")).env()
# pkg-config 解析必须只看目标 sysroot。实现：宿主 pkgconf 二进制
# + PKG_CONFIG_SYSROOT_DIR（-I/-L 自动加 sysroot 前缀）
# + PKG_CONFIG_LIBDIR（只在 sysroot 里找 .pc）。
# 之前往 sysroot 塞 shell 包装器的做法废弃了：那是构建产物目录，
# 会被打包/回滚逻辑当成系统文件，清理时就消失。
assert "PKG_CONFIG_SYSROOT_DIR" in e and str(e["PKG_CONFIG_SYSROOT_DIR"]).startswith("/opt/root"), \
    f"SYSROOT_DIR 没指到目标: {e.get('PKG_CONFIG_SYSROOT_DIR')}"
assert "/opt/root/usr/lib/pkgconfig" in e.get("PKG_CONFIG_LIBDIR", ""), \
    f"LIBDIR 没限定到目标 sysroot: {e.get('PKG_CONFIG_LIBDIR')}"
assert e.get("PKG_CONFIG"), "PKG_CONFIG 未设置"
print("  pkg-config 解析限定在目标 sysroot（宿主二进制 + SYSROOT_DIR/LIBDIR）")
PYEOF
[ $? -eq 0 ] && ok "pkg-config 用目标机的（不会误链宿主库）" || bad "pkg-config 配置错误"

step "5. --target 只给编译器类包"
A=$(./bin/qycross args --host aarch64 --name zlib)
B=$(./bin/qycross args --host aarch64 --target aarch64 --name gcc)
echo "$A" | grep -q "target" && bad "普通包不该有 --target" || ok "zlib 不带 --target"
echo "$B" | grep -q "target" && ok "gcc 带 --target" || bad "gcc 缺 --target"
echo "$A" | grep -q "\--build=" && echo "$A" | grep -q "\--host=" \
  && ok "--build 与 --host 配对给出" || bad "参数不全"

step "6. CMake 与 meson 交叉文件"
./bin/qycross cmake --host aarch64 --sysroot /opt/root > "$TMP/cm.txt" 2>&1
grep -q "CMAKE_SYSTEM_PROCESSOR aarch64" "$TMP/cm.txt" \
  && ok "CMake 指定了目标处理器" || bad "CMake 文件不对"
grep -q "CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER" "$TMP/cm.txt" \
  && ok "CMake 不从宿主找程序" || bad "CMake 会误用宿主程序"
./bin/qycross meson --host aarch64 --sysroot /opt/root > "$TMP/ms.txt" 2>&1
grep -q "cpu_family = 'aarch64'" "$TMP/ms.txt" \
  && ok "meson 指定了 cpu_family" || bad "meson 文件不对"

step "7. 架构校验能抓出错架构"
./bin/qycross check /bin/ls --arch x86_64 >/dev/null 2>&1 \
  && ok "同架构 → 通过" || bad "同架构误报"
./bin/qycross check /bin/ls --arch aarch64 >/dev/null 2>&1 \
  && bad "异架构竟然通过" || ok "异架构 → 拒绝"

step "8. 工具链缺失检测"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import crosstool as CT
missing = CT.check_toolchain("aarch64")
assert missing, "本环境没有 aarch64 工具链，应报缺失"
assert any("gcc" in m for m in missing), f"应包含 gcc: {missing}"
print(f"  检测到缺失 {len(missing)} 个工具，例如 {missing[0]}")
PYEOF
[ $? -eq 0 ] && ok "能检测交叉工具链是否就绪" || bad "工具链检测无效"

step "9. 交叉编译缺工具链时给可行动的诊断"
./bin/qybuild --target-arch aarch64 qydemo --force > "$TMP/x.txt" 2>&1
grep -q "交叉工具链" "$TMP/x.txt" \
  && ok "提示了交叉工具链缺失（而非只报命令失败）" || bad "诊断缺失"
grep -q "先编出交叉工具链\|apt install" "$TMP/x.txt" \
  && ok "给出了怎么解决" || bad "未给出解法"

step "10. 交叉环境自动注入 ctx"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import crosstool as CT
from qyos import builder as B
from pathlib import Path
# 交叉模式下上下文必须自带 CC，177 个包靠每个配方自己写必然写漏
class Log:
    def __call__(self, *a): pass
sb = type("S", (), {"jobs": 1})()
ctx = B.BuildContext(
    type("R", (), {"name": "zlib", "version": "1.0"})(),
    {"srcdir": Path("/tmp"), "builddir": Path("/tmp"),
     "destdir": Path("/tmp"), "pkgdir": Path("/tmp")},
    sb, Log(), cross=CT.Triple(build="x86_64", host="aarch64"))
assert ctx.env_extra.get("CC", "").startswith("aarch64-"), \
    f"CC 未注入: {ctx.env_extra}"
print(f"  ctx.env_extra['CC'] = {ctx.env_extra['CC']}")
args = ctx.configure_args()
assert "--host=aarch64-qiyuan-linux-gnu" in args, f"参数不对: {args}"
print(f"  ctx.configure_args() = {' '.join(args)}")
# 原生模式不该注入
ctx2 = B.BuildContext(
    type("R", (), {"name": "zlib", "version": "1.0"})(),
    {"srcdir": Path("/tmp"), "builddir": Path("/tmp"),
     "destdir": Path("/tmp"), "pkgdir": Path("/tmp")},
    sb, Log(), cross=None)
assert not ctx2.env_extra, f"原生模式不该注入: {ctx2.env_extra}"
print("  原生模式不注入，行为不变")
PYEOF
[ $? -eq 0 ] && ok "交叉环境自动注入且原生不受影响" || bad "注入逻辑不正确"

step "11. 原生构建未因交叉改动退化"
rm -rf var/work
./bin/qybuild all --sign var/repo/keys/qiyuan --force >/dev/null 2>&1 \
  && ok "原生全量构建仍通过" || bad "原生构建出现回归"
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1

step "12. 清理"
for _ in 1 2 3; do rm -rf "$TMP" 2>/dev/null; [ -e "$TMP" ] || break; sleep 1; done
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
