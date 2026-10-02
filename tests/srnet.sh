#!/usr/bin/env bash
# 软件源管理与网络服务专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
TMP=/tmp/qy-srcnet
qyrm(){ for _ in 1 2 3 4 5; do rm -rf "$@" 2>/dev/null; gone=1; \
  for t in "$@"; do [ -e "$t" ] && gone=0; done; [ "$gone" -eq 1 ] && return 0; sleep 1; done; return 1; }
qyrm "$TMP"; mkdir -p "$TMP"

step "1. 默认源：本地优先于远程"
qyrm "$TMP/r1"; mkdir -p "$TMP/r1"
./bin/qysource --root "$TMP/r1" list > "$TMP/list.txt" 2>&1
grep -q "local" "$TMP/list.txt" && grep -q "official" "$TMP/list.txt" \
  && ok "默认给出本地源与官方源" || bad "默认源不完整"
grep -q "数字小者优先" "$TMP/list.txt" \
  && ok "说明了优先级含义" || bad "未说明优先级"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sources as S
from pathlib import Path
# 本地源优先级必须高于远程：自己构建的包应优先于远程同名包，
# 否则本地改了代码却装到远程旧包，表现为"我明明改了怎么没生效"
srcs = S.default_sources(Path('.'))
act = S.active_sources(srcs)
assert act[0].name == "local", f"本地源不是最高优先级: {act[0].name}"
print(f"  最高优先级是 {act[0].name}({act[0].priority})")
PYEOF
[ $? -eq 0 ] && ok "本地源优先级最高" || bad "优先级设计不对"

step "2. 同优先级排序必须确定"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sources as S
# 同优先级时按名字排序，否则两次解析可能拿到不同源，
# 装到的包也就不同了——这种不可复现最难排查
srcs = [S.Source(name="b", url="/b", priority=50),
        S.Source(name="a", url="/a", priority=50),
        S.Source(name="c", url="/c", priority=10)]
first = [s.name for s in S.active_sources(srcs)]
srcs2 = list(reversed(srcs))        # 换个声明顺序
second = [s.name for s in S.active_sources(srcs2)]
assert first == second == ["c", "a", "b"], f"结果不稳定: {first} vs {second}"
print(f"  换声明顺序结果一致: {first}")
PYEOF
[ $? -eq 0 ] && ok "排序确定（与声明顺序无关）" || bad "排序不稳定"

step "3. 源失效要降级到下一个，并说清原因"
qyrm "$TMP/r2"; mkdir -p "$TMP/r2"
./bin/qysource --root "$TMP/r2" resolve qydemo > "$TMP/res.txt" 2>&1
grep -q "没找到" "$TMP/res.txt" && ok "源不可用时报告没找到" || bad "解析输出不对"
grep -qE "不可用|没有这个包" "$TMP/res.txt" \
  && ok "说明了每个源为什么没命中" || bad "未给出原因"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import sources as S
# 真实的降级：第一个源没有这个包，第二个源有
import tempfile, json, pathlib
root = pathlib.Path(tempfile.mkdtemp())
for n, pkgs in (("s1", []), ("s2", ["qydemo"])):
    d = root / n / "x86_64"; d.mkdir(parents=True)
    (d / "index.json").write_text(json.dumps({
        "arch": "x86_64", "packages": [
            {"name": p, "version": "1.0", "release": 1,
             "pkgid": f"{p}-1.0-1", "filename": f"{p}.qyp"}
            for p in pkgs]}))
S.save_sources(root, [S.Source(name="s1", url=str(root/"s1"), priority=10,
                               trust=S.LOCAL),
                      S.Source(name="s2", url=str(root/"s2"), priority=20,
                               trust=S.LOCAL)])
r = S.resolve(root, ["qydemo"])
assert r["qydemo"].found, "没降级到第二个源"
assert r["qydemo"].entry["_source"] == "s2", \
    f"来源不对: {r['qydemo'].entry['_source']}"
print("  s1 没有 → 自动降级到 s2")
PYEOF
[ $? -eq 0 ] && ok "第一个源没有时自动降级" || bad "降级不生效"

step "4. 所有源都不可达要明确说出来"
python3 - <<'PYEOF'
import sys, tempfile; sys.path.insert(0, '.')
from qyos import sources as S
import pathlib
# 单个源挂了只是提醒，全部挂了必须明确——
# 那意味着这台机器装不了任何软件。
# 这里造一个只有远程源的 root（项目根下的本地源是好的，
# 用它测不出"全挂"这条路径）
root = pathlib.Path(tempfile.mkdtemp())
S.save_sources(root, [S.Source(name="x", url="https://nope.invalid",
                               priority=10)])
probs = S.check_sources(root, timeout=2)
joined = " ".join(probs)
assert "所有源都不可达" in joined, f"未指出全部不可达: {probs}"
print("  全部不可达 → 明确报出")
PYEOF
[ $? -eq 0 ] && ok "全源不可达会明确告警" || bad "未区分单源与全源故障"

step "5. 未签名源必须显式允许"
python3 - <<'PYEOF'
import sys, tempfile, json; sys.path.insert(0, '.')
from qyos import sources as S
import pathlib
root = pathlib.Path(tempfile.mkdtemp())
d = root / "uns" / "x86_64"; d.mkdir(parents=True)
(d/"index.json").write_text(json.dumps({"arch": "x86_64", "packages": [
    {"name": "qydemo", "version": "1.0", "release": 1,
     "pkgid": "qydemo-1.0-1", "filename": "qydemo.qyp"}]}))
S.save_sources(root, [S.Source(name="uns", url=str(root/"uns"),
                               priority=10, trust=S.UNSIGNED)])
r = S.resolve(root, ["qydemo"], allow_unsigned=False)
assert not r["qydemo"].found, "未签名的源竟被接受"
assert any("未签名" in w for _, w in r["qydemo"].tried), \
    f"未说明原因: {r['qydemo'].tried}"
print("  未签名且未允许 → 拒绝并说明需 --allow-unsigned")
r2 = S.resolve(root, ["qydemo"], allow_unsigned=True)
assert r2["qydemo"].found, "显式允许后仍被拒"
print("  显式允许后 → 接受")
PYEOF
[ $? -eq 0 ] && ok "未签名源需显式允许" || bad "信任控制不正确"

step "6. 端口冲突要指出是谁占了"
qyrm "$TMP/net"; mkdir -p "$TMP/net"
./bin/qynet --root "$TMP/net" add-port postgresql 5432 --desc "数据库" \
  >/dev/null 2>&1 && ok "能登记端口" || bad "登记失败"
./bin/qynet --root "$TMP/net" add-port other 5432 > "$TMP/conf.txt" 2>&1
grep -q "已被 postgresql 占用" "$TMP/conf.txt" \
  && ok "冲突时指出占用方" || bad "冲突信息不完整"
grep -q "Traceback" "$TMP/conf.txt" \
  && bad "抛了栈，用户看不清" || ok "报错可读（无 traceback）"

step "7. 特权端口与对外暴露要标注"
./bin/qynet --root "$TMP/net" add-port ssh 22 --bind 0.0.0.0 --desc "远程" \
  >/dev/null 2>&1
./bin/qynet --root "$TMP/net" ports > "$TMP/ports.txt" 2>&1
grep -q "需特权" "$TMP/ports.txt" && ok "标出了特权端口" || bad "未标特权"
grep -q "对外暴露" "$TMP/ports.txt" && ok "标出了对外暴露" || bad "未标暴露"
grep -q "确认这些是真正需要对外的" "$TMP/ports.txt" \
  && ok "提示复核对外暴露的服务" || bad "未提示复核"

step "8. 防火墙只放行对外暴露的端口"
./bin/qynet --root "$TMP/net" firewall > "$TMP/fw.txt" 2>&1
grep -q "dport 22 accept" "$TMP/fw.txt" \
  && ok "放行了对外暴露的 22" || bad "该放行的没放行"
grep -q "dport 5432" "$TMP/fw.txt" \
  && bad "只听本机的端口不该放行" || ok "只听本机的 5432 未放行"
grep -q "ct state established,related accept" "$TMP/fw.txt" \
  && grep -q "iif lo accept" "$TMP/fw.txt" \
  && ok "保留了已建立连接与回环（否则锁死机器）" || bad "缺关键放行规则"

step "9. sshd 默认安全，危险配置要警告"
./bin/qynet --root "$TMP/net" ssh > "$TMP/ssh.txt" 2>&1
grep -q "PasswordAuthentication no" "$TMP/ssh.txt" \
  && grep -q "PermitRootLogin prohibit-password" "$TMP/ssh.txt" \
  && ok "默认禁密码、禁 root 直接登录" || bad "默认配置不安全"
./bin/qynet --root "$TMP/net" ssh --allow-root --password-auth \
  > "$TMP/ssh2.txt" 2>&1
grep -q "会持续被暴力破解" "$TMP/ssh2.txt" \
  && ok "开了密码登录会警告" || bad "未警告密码登录"
grep -q "一旦密码泄露整机失守" "$TMP/ssh2.txt" \
  && ok "开了 root 登录会警告" || bad "未警告 root 登录"

step "10. FTP 默认不匿名、限制目录，并提示明文风险"
./bin/qynet --root "$TMP/net" ftp > "$TMP/ftp.txt" 2>&1
grep -q "anonymous_enable=NO" "$TMP/ftp.txt" \
  && ok "默认不开匿名访问" || bad "默认开了匿名"
grep -q "chroot_local_user=YES" "$TMP/ftp.txt" \
  && ok "默认限制在用户目录" || bad "未限制目录"
grep -q "明文" "$TMP/ftp.txt" && grep -q "!!" "$TMP/ftp.txt" \
  && ok "提示了明文传输风险" || bad "未提示明文风险"
grep -q "pasv_min_port" "$TMP/ftp.txt" && grep -q "pasv_max_port" "$TMP/ftp.txt" \
  && ok "固定了被动端口范围（防火墙不必全开）" || bad "未固定被动端口"

step "11. 共享存储：路径不存在必须报错"
python3 - <<'PYEOF'
import sys, tempfile; sys.path.insert(0, '.')
from qyos import net as N
import pathlib
root = pathlib.Path(tempfile.mkdtemp())
(root/"data").mkdir()
ex = [N.Export(path="/data", clients="192.168.1.0/24"),
      N.Export(path="/nonexistent", clients="*"),
      N.Export(path="/data", clients="*", options="rw,no_root_squash")]
probs = N.check_exports(root, ex)
joined = " ".join(probs)
assert "不存在" in joined, f"未检出不存在的路径: {probs}"
print("  导出不存在的路径 → 报错")
assert "对所有客户端开放" in joined, "未警告全网开放"
print("  clients=* → 警告应限定网段")
assert "no_root_squash" in joined, "未警告 no_root_squash"
print("  no_root_squash → 警告客户端 root 等于本机 root")
# 好的配置不该报
good = [N.Export(path="/data", clients="192.168.1.0/24")]
assert not N.check_exports(root, good), f"正常配置被误报: {N.check_exports(root, good)}"
print("  限定网段 + 存在路径 → 无误报")
PYEOF
[ $? -eq 0 ] && ok "共享存储三类风险全检出且不误报" || bad "共享存储校验不正确"

step "12. 穿透无鉴权必须警告"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import net as N
t = [N.Tunnel(name="web", local_port=8080, public_port=80),
     N.Tunnel(name="safe", local_port=9000, public_port=443, auth="token")]
w = N.check_tunnels(t)
joined = " ".join(w)
assert "web" in joined and "没有鉴权" in joined, f"未警告无鉴权: {w}"
print("  无鉴权穿透 → 警告任何人都能访问")
assert not any("safe" in x for x in w), f"有鉴权的被误报: {w}"
print("  有鉴权的 → 不报（无误报）")
PYEOF
[ $? -eq 0 ] && ok "穿透风险检出且不误报" || bad "穿透校验不正确"

step "13. 清理"
qyrm "$TMP"
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
