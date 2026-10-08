#!/bin/bash
# 自举闭环验证：Stage1 用 seed 编 moc；Stage2 用 moc 编自己；比对字节
set -e
cd "$(dirname "$0")"
rm -rf /tmp/moboot && mkdir -p /tmp/moboot/{s1,s2,s3}

cp src/compiler.mo /tmp/moboot/s1/test.mo
( cd /tmp/moboot/s1 && "$OLDPWD/bin/seed" test.mo out.elf )

cp src/compiler.mo /tmp/moboot/s2/test.mo
cp /tmp/moboot/s1/out.elf /tmp/moboot/s2/moc1 && chmod +x /tmp/moboot/s2/moc1
( cd /tmp/moboot/s2 && ./moc1 )

cp src/compiler.mo /tmp/moboot/s3/test.mo
cp /tmp/moboot/s2/out.elf /tmp/moboot/s3/moc2 && chmod +x /tmp/moboot/s3/moc2
( cd /tmp/moboot/s3 && ./moc2 )

echo "Stage1 (seed 编译):  $(md5sum /tmp/moboot/s1/out.elf | cut -d' ' -f1)"
echo "Stage2 (moc  编译):  $(md5sum /tmp/moboot/s2/out.elf | cut -d' ' -f1)"
echo "Stage3 (moc  再编):  $(md5sum /tmp/moboot/s3/out.elf | cut -d' ' -f1)"
if cmp -s /tmp/moboot/s1/out.elf /tmp/moboot/s2/out.elf && cmp -s /tmp/moboot/s2/out.elf /tmp/moboot/s3/out.elf; then
  echo "✅ 自举闭环成立：三个 Stage 产物字节完全一致"
else
  echo "❌ 自举不一致"; exit 1
fi
