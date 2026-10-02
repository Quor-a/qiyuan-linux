#!/usr/bin/env bash
# 安全响应、形态与发布专项测试
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step(){ echo; echo "== $1"; }
ADV=/tmp/qy-sec-test.json
ROOT=/tmp/qy-sec-root

step "1. 版本区间判定：不能只查版本号相等"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import security as S
a = S.Affected('libqydemo', '0.1.0', '0.2.0')
# CVE 影响 0.1.0 ~ 0.2.0 之间的所有版本，只查 ==0.1.0 会漏掉 0.1.5
for v, want in (('0.0.9', False), ('0.1.0', True), ('0.1.5', True),
                ('0.1.99', True), ('0.2.0', False), ('0.3.0', False)):
    got = a.is_affected(v)
    assert got == want, f"{v} 期望{want} 实得{got}"
    print(f"  {v}: 受影响={got}")
# 未修复的情况
b = S.Advisory('QYSA-T2', '未修复漏洞', S.HIGH,
               affected=[S.Affected('foo', '1.0', None)])
assert b.affected[0].is_affected('1.5')
assert not b.affected[0].is_fixed('1.5')
print("  未修复版本区间判定正确")
PYEOF
[ $? -eq 0 ] && ok "按区间判定而非相等，未修复情形也正确" || bad "版本区间判定错误"

step "2. 版本号比较要兼容常见写法"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import security as S
cmp = S._vcmp
cases = [('1.2.3', '1.2.4', -1), ('1.10.0', '1.9.0', 1),   # 不能按字符串比
         ('1.0rc1', '1.0', -1),                            # rc 早于正式版
         ('2.0', '10.0', -1),                              # 数字而非字典序
         ('1.2.3-4', '1.2.3-5', 0),                        # 发行号不参与
         ('1.2.3+deb1', '1.2.3', 0)]                       # 本地版本不参与
for a, b, want in cases:
    got = cmp(a, b)
    got = (got > 0) - (got < 0)
    assert got == want, f"{a} vs {b}: 期望{want} 实得{got}"
    print(f"  {a:12s} vs {b:10s} → {got}")
PYEOF
[ $? -eq 0 ] && ok "版本号比较正确处理 rc / 数字段 / 后缀" || bad "版本比较不正确"

step "3. 扫描已装系统报出漏洞"
rm -f "$ADV"; rm -rf "$ROOT"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import security as S
from pathlib import Path
db = S.AdvisoryDB(Path('/tmp/qy-sec-test.json'))
db.add(S.Advisory(
    id='QYSA-2026-0001', title='libqydemo 栈溢出可导致远程代码执行',
    severity=S.CRITICAL, cves=['CVE-2026-0001'],
    affected=[S.Affected('libqydemo', '0.1.0', '0.2.0'),
              S.Affected('qydemo', '0.1.0', None)]))
print("公告已建立")
PYEOF
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
./bin/qypkg --root "$ROOT" assemble filesystem qyinit qydemo >/dev/null 2>&1
./bin/qysec scan --root "$ROOT" --db "$ADV" >/tmp/qy-scan.log 2>&1
grep -q "发现 2 个问题" /tmp/qy-scan.log && ok "扫出 2 个受影响包" \
  || { bad "扫描结果不符"; cat /tmp/qy-scan.log; }
grep -q "待上游修复" /tmp/qy-scan.log && ok "区分可修复与待上游修复" \
  || bad "未区分修复状态"
grep -q "critical" /tmp/qy-scan.log && ok "按严重级别归类" || bad "未归类"

step "4. 干净系统不应误报"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import security as S
from pathlib import Path
db = S.AdvisoryDB(Path('/tmp/qy-sec-test.json'))
# 把已装版本换成已修复版本后应无告警
db.advisories['QYSA-2026-0001'].affected = [
    S.Affected('libqydemo', '0.1.0', '0.1.0')]
db.save()
r = S.scan_system(Path('/tmp/qy-sec-root'), db)
assert r['total'] == 0, f"不应有告警: {r['findings']}"
print("已修复版本不再告警")
PYEOF
[ $? -eq 0 ] && ok "已修复版本不再告警（无误报）" || bad "存在误报"

step "5. 改一个包要算出谁必须重编"
./bin/qysec rebuild --changed linux-headers >/tmp/qy-rb.log 2>&1
grep -q "binutils" /tmp/qy-rb.log && grep -q "gcc" /tmp/qy-rb.log \
  && ok "内核头文件改动会牵连整个工具链" \
  || { bad "重建闭包不正确"; cat /tmp/qy-rb.log; }
# 不写死数量：配方库会扩充，硬编码的数字每次加包就得改，
# 而且改漏了会变成假失败。这里校验的是"闭包非空且不含自己"这个性质
n=$(grep -cE "^  [a-z]" /tmp/qy-rb.log)
[ "$n" -ge 3 ] && ok "重建闭包规模合理（$n 个）" || bad "重建数量不对（$n）"
grep -q "^  linux-headers" /tmp/qy-rb.log && bad "闭包包含了被改的包自己" \
  || ok "闭包不含被改的包自己"

step "6. 修复优先级"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import security as S
rce = S.Advisory('A1', 'libfoo 远程代码执行漏洞', S.CRITICAL,
                 description='未校验输入长度导致 RCE')
prio = S.Advisory('A2', 'libbar 本地提权', S.HIGH)
low = S.Advisory('A3', 'libbaz 文档拼写错误', S.LOW)
r1 = S.priority(rce); r2 = S.priority(prio); r3 = S.priority(low)
assert r1[0] < r2[0] < r3[0], (r1, r2, r3)
print("  RCE:", r1[1]); print("  提权:", r2[1]); print("  低级:", r3[1])
PYEOF
[ $? -eq 0 ] && ok "优先级按严重程度与漏洞类型排序" || bad "优先级排序错误"

step "7. 系统形态（profile）定义与校验"
./bin/qyrelease profiles >/tmp/qy-pf.log 2>&1
grep -q "minimal" /tmp/qy-pf.log && grep -q "server" /tmp/qy-pf.log \
  && grep -q "desktop" /tmp/qy-pf.log && ok "内置三种以上形态" || bad "形态不全"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import profile as PF
from qyos import recipe as R
from pathlib import Path
available = set(R.load_tree(Path('recipes')))
for name, p in PF.PROFILES.items():
    v = PF.validate(p, available)
    assert v['ok'], f"{name}: {v['errors']}"
    assert p.excludes, f"{name} 未声明排除项"
print("全部形态校验通过，且都声明了排除项")
PYEOF
[ $? -eq 0 ] && ok "形态校验通过且都声明了排除项" || bad "形态定义不合格"

step "8. 形态资源需求要自洽"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import profile as PF
d = PF.get('desktop'); s = PF.get('server'); m = PF.get('minimal')
assert d.min_disk > s.min_disk > m.min_disk, "磁盘需求应递增"
assert d.min_memory > s.min_memory > m.min_memory, "内存需求应递增"
assert d.graphical and not s.graphical and not m.graphical
assert 'net.ipv4.ip_forward' in s.sysctl, "服务器形态应开启转发"
print(f"  minimal {PF.util.human_size(m.min_disk)} / server "
      f"{PF.util.human_size(s.min_disk)} / desktop {PF.util.human_size(d.min_disk)}")
PYEOF
[ $? -eq 0 ] && ok "资源需求随形态递增且自洽" || bad "资源需求不自洽"

step "9. 版本号递增规则"
python3 - <<'PYEOF'
import sys; sys.path.insert(0, '.')
from qyos import release as RL
v = RL.Version.parse('0.1.0-alpha.3')
assert str(v.next('stage')) == '0.1.0-alpha.4', '阶段内递增'
assert str(v.next('promote')) == '0.1.0-beta.1', '阶段推进'
assert str(RL.Version.parse('0.1.0-rc.2').next('promote')) == '0.1.0', 'rc→稳定'
assert str(RL.Version.parse('1.0.0').next('minor')) == '1.1.0'
assert RL.Version.parse('0.1.0-beta.1').key() < RL.Version.parse('0.1.0').key(), \
    '稳定版应排在 beta 之后'
try:
    RL.Version.parse('1.0')
    raise AssertionError('非法版本号未被拒绝')
except RL.ReleaseError:
    pass
print("  0.1.0-alpha.3 → stage=0.1.0-alpha.4, promote=0.1.0-beta.1")
PYEOF
[ $? -eq 0 ] && ok "版本号递增与校验正确" || bad "版本号规则不正确"

step "10. 发布清单：签名 + 每个产物校验和"
rm -rf /tmp/qy-rel && mkdir -p /tmp/qy-rel
head -c 65536 /dev/zero > /tmp/qy-rel/qiyuan-0.1.0.img
head -c 2048 /dev/zero > /tmp/qy-rel/packages.tar.gz
./bin/qyrelease manifest --dir /tmp/qy-rel --version 0.1.0-alpha.1 \
  --kernel 6.16.1 --sign var/repo/keys/qiyuan >/tmp/qy-mf.log 2>&1
grep -q "发布清单已写入" /tmp/qy-mf.log && ok "发布清单生成成功" \
  || { bad "清单生成失败"; cat /tmp/qy-mf.log; }
./bin/qyrelease verify --dir /tmp/qy-rel --pubkey var/repo/keys/qiyuan.pub \
  >/tmp/qy-vf.log 2>&1 && ok "发布校验通过（签名 + 2 个产物）" \
  || { bad "校验失败"; cat /tmp/qy-vf.log; }

step "11. 产物被替换必须被检出"
head -c 65536 /dev/urandom > /tmp/qy-rel/qiyuan-0.1.0.img
./bin/qyrelease verify --dir /tmp/qy-rel --pubkey var/repo/keys/qiyuan.pub \
  >/tmp/qy-vf2.log 2>&1
[ $? -ne 0 ] && grep -q "校验和不符" /tmp/qy-vf2.log \
  && ok "产物被替换被检出" || bad "替换产物未被检出"
# 清单本身被篡改也要被检出
python3 - <<'PYEOF'
import json, pathlib
p = pathlib.Path('/tmp/qy-rel/RELEASE.json')
d = json.loads(p.read_text()); d['version'] = '9.9.9'
p.write_text(json.dumps(d, ensure_ascii=False, sort_keys=True, separators=(',',':')))
PYEOF
./bin/qyrelease verify --dir /tmp/qy-rel --pubkey var/repo/keys/qiyuan.pub \
  >/tmp/qy-vf3.log 2>&1
[ $? -ne 0 ] && grep -q "签名校验失败" /tmp/qy-vf3.log \
  && ok "清单本身被篡改被检出" || bad "篡改清单未被检出"

step "12. 无签名密钥重写索引不得留下陈旧签名"
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1
./bin/qyrepo index >/tmp/qy-idx.log 2>&1
grep -q "已删除过期的旧签名文件" /tmp/qy-idx.log \
  && ok "重写未签名索引时清掉了旧签名" || bad "留下陈旧签名会导致误报篡改"
# 恢复成已签名状态
./bin/qyrepo sync --sign var/repo/keys/qiyuan >/dev/null 2>&1

step "13. 清理"
rm -rf "$ADV" "$ROOT" /tmp/qy-rel /tmp/qy-scan.log /tmp/qy-rb.log \
       /tmp/qy-pf.log /tmp/qy-mf.log /tmp/qy-vf.log /tmp/qy-vf2.log \
       /tmp/qy-vf3.log /tmp/qy-idx.log
ok "测试产物已清理"

echo
echo "======================================="
echo " 通过 $PASS 项，失败 $FAIL 项"
echo "======================================="
[ "$FAIL" -eq 0 ] || exit 1
