#!/bin/bash
# 多后端一致性测试
#
# 同一个 .mo 源，分别用四种方式跑，退出码必须全部相同：
#   1) 原生后端    moc      -> ELF
#   2) C 后端      mo2x c   -> gcc
#   3) JS 后端     mo2x js  -> node
#   4) Python 后端 mo2x py  -> python3
#   5) Perl  后端 mo2x perl -> perl
#
# 多后端的价值取决于「它们行为一致」。没有这个测试，
# 每个后端都只是能跑，而不是对齐。
set +e
cd "$(dirname "$0")/.."
MOC=./bin/moc
MO2X=./bin/mo2x
TMP=/tmp/momb
rm -rf $TMP && mkdir -p $TMP
[ -x "$MO2X" ] || { echo "先编出 bin/mo2x：moc tools/mo2x.mo bin/mo2x"; exit 1; }
HAVE_GCC=0; command -v gcc     >/dev/null && HAVE_GCC=1
HAVE_JS=0;  command -v node    >/dev/null && HAVE_JS=1
HAVE_PY=0;  command -v python3 >/dev/null && HAVE_PY=1
HAVE_PL=0;  command -v perl    >/dev/null && HAVE_PL=1

FAIL=0; PASS=0
for f in tests/multibackend/*.mo; do
  b=$(basename $f .mo)
  exp=$(grep -m1 '# expect:' "$f" | sed 's/.*expect: *//')
  [ -z "$exp" ] && exp=0
  cp "$f" $TMP/test.mo
  ( cd $TMP && $OLDPWD/$MOC >/dev/null 2>&1 )
  if [ $? -ne 0 ]; then echo "FAIL $b 原生后端编译失败"; FAIL=$((FAIL+1)); continue; fi
  chmod +x $TMP/out.elf
  ( cd $TMP && ./out.elf ); r0=$?
  ok=1; msg=""
  [ "$r0" != "$exp" ] && { ok=0; msg="$msg 原生=$r0"; }

  if [ $HAVE_GCC -eq 1 ]; then
    ( cd $TMP && $OLDPWD/$MO2X test.mo c > t.c 2>/dev/null )
    if [ $? -ne 0 ]; then msg="$msg C=不支持"; else
      gcc -O2 -o $TMP/t_c $TMP/t.c 2>/dev/null
      if [ $? -ne 0 ]; then msg="$msg C=gcc失败"; ok=0; else
        ( cd $TMP && ./t_c ); r1=$?
        [ "$r1" != "$exp" ] && { ok=0; msg="$msg C=$r1"; }
      fi
    fi
  fi

  if [ $HAVE_JS -eq 1 ]; then
    ( cd $TMP && $OLDPWD/$MO2X test.mo js > t.js 2>/dev/null )
    if [ $? -ne 0 ]; then msg="$msg JS=不支持"; else
      ( cd $TMP && node t.js ); r2=$?
      [ "$r2" != "$exp" ] && { ok=0; msg="$msg JS=$r2"; }
    fi
  fi

  if [ $HAVE_PY -eq 1 ]; then
    ( cd $TMP && $OLDPWD/$MO2X test.mo py > t.py 2>/dev/null )
    if [ $? -ne 0 ]; then msg="$msg PY=不支持"; else
      ( cd $TMP && python3 t.py ); r3=$?
      [ "$r3" != "$exp" ] && { ok=0; msg="$msg PY=$r3"; }
    fi
  fi

  if [ $HAVE_PL -eq 1 ]; then
    ( cd $TMP && $OLDPWD/$MO2X test.mo perl > t.pl 2>/dev/null )
    if [ $? -ne 0 ]; then msg="$msg PERL=不支持"; else
      ( cd $TMP && perl t.pl ); r4=$?
      [ "$r4" != "$exp" ] && { ok=0; msg="$msg PERL=$r4"; }
    fi
  fi

  if [ $ok -eq 1 ]; then PASS=$((PASS+1)); else echo "FAIL $b 期望$exp:$msg"; FAIL=$((FAIL+1)); fi
done
echo "multibackend: 通过 $PASS / 失败 $FAIL（原生 + C + JS + Python + Perl）"
[ $FAIL -eq 0 ] || exit 1
