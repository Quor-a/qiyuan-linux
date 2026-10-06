#!/bin/bash
# build-qyrepo.sh — 组装 ISO 内置离线软件仓库 (v1.9.5 软件中心 qystore 数据源)
# 从 var/pkgs 挑选 <=1.5MB 的包 (109/147) + index.json 复制到 sysroot/usr/share/qyrepo
set -e
Q="$(cd "$(dirname "$0")/.." && pwd)"
D="$Q/var/sysroot/usr/share/qyrepo"
mkdir -p "$D/pkgs"
rm -f "$D"/pkgs/*.qyp
QYQ="$Q" python3 - <<'EOF'
import json, os, shutil
Q = os.environ["QYQ"]
src_idx = json.load(open(Q + "/var/repo/x86_64/index.json"))
out = dict(src_idx)
sel = []
for p in src_idx["packages"]:
    if p.get("size", 10**9) <= 1_500_000:
        src = Q + "/var/pkgs/" + p["filename"]
        if os.path.exists(src):
            shutil.copy(src, Q + "/var/sysroot/usr/share/qyrepo/pkgs/")
            sel.append(p)
out["packages"] = sel
with open(Q + "/var/sysroot/usr/share/qyrepo/index.json", "w") as f:
    json.dump(out, f, indent=2)
print("qyrepo:", len(sel), "packages")
EOF
chmod -R a+rX "$D"
du -sh "$D"
echo QYREPO-DONE
