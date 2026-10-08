#!/bin/bash
# mo —— 墨语言统一命令行（构建 / 运行 / 测试 / 格式化 / 信息）
#
#   mo build <file.mo> [-o out]   编译
#   mo run   <file.mo> [args...]  编译并立即运行（脚本式体验）
#   mo test                       跑全部测试
#   mo boot                       验证自举
#   mo fmt   [-w] <file.mo>       格式化
#   mo size  <file.mo>            看代码段大小
#   mo info  <file>               查看文件魔数与元数据
#   mo version                    版本号
#   mo clean                      清理产物
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
MOC=$ROOT/bin/moc

need_moc() {
  [ -x "$MOC" ] || { echo "没有 bin/moc，先跑 make"; exit 1; }
}

case "${1:-}" in
  build)
    need_moc; shift
    src="$1"; shift || true
    out="${2:-${src%.mo}.elf}"
    [ -n "$1" ] && out="$1"
    "$MOC" "$src" "$out"
    chmod +x "$out"
    echo "-> $out"
    ;;
  run)
    need_moc; shift
    src="$1"; shift || true
    case "$src" in /*) ;; *) src="$ROOT/$src";; esac
    tmp=/tmp/morun.$$
    mkdir -p $tmp
    cp "$src" $tmp/t.mo
    cp lib/*.mo $tmp/ 2>/dev/null || true
    ( cd $tmp && "$MOC" t.mo t.elf )
    chmod +x $tmp/t.elf
    ( cd $tmp && ./t.elf "$@" )
    rc=$?
    rm -rf $tmp
    exit $rc
    ;;
  test)  need_moc; bash tests/run.sh "$MOC" ;;
  boot)  need_moc; bash verify_bootstrap.sh ;;
  fmt)   need_moc; shift; bash -c "$(echo cp tools/fmt.mo /tmp/mofmt.mo)"; \
         cp lib/*.mo /tmp/ 2>/dev/null; ( cd /tmp && "$MOC" mofmt.mo mofmt.elf ) ; \
         chmod +x /tmp/mofmt.elf; /tmp/mofmt.elf "$@" ;;
  size)  need_moc; shift; bash tools/codesize.sh "$@" ;;
  cbuild)
    need_moc; shift
    src="$1"; shift || true
    case "$src" in /*) ;; *) src="$ROOT/$src";; esac
    out="${1:-/tmp/mo_cbuild.bin}"
    [ -x bin/mo2x ] || { echo "先编出 bin/mo2x：moc tools/mo2x.mo bin/mo2x"; exit 1; }
    ./bin/mo2x "$src" c > /tmp/mo_cbuild.c
    gcc -O2 -o "$out" /tmp/mo_cbuild.c
    echo "-> $out （经 C 后端 + gcc）"
    ;;
  x2)
    need_moc; shift
    src="$1"; shift || true
    tgt="${2:-c}"
    case "$src" in /*) ;; *) src="$ROOT/$src";; esac
    [ -x bin/mo2x ] || { echo "先编出 bin/mo2x：moc tools/mo2x.mo bin/mo2x"; exit 1; }
    ./bin/mo2x "$src" "$tgt"
    ;;
  ctest) bash tools/multibackend_test.sh ;;
  dep)   need_moc; bash tools/depcheck.sh ;;
  info)
    need_moc; shift
    case "$1" in /*) ARG="$1";; *) ARG="$ROOT/$1";; esac
    rm -rf /tmp/moi && mkdir -p /tmp/moi
    cp lib/*.mo /tmp/moi/
    cp tools/info.mo /tmp/moi/info.mo
    ( cd /tmp/moi && "$MOC" info.mo info.elf )
    chmod +x /tmp/moi/info.elf
    /tmp/moi/info.elf "$ARG"
    ;;
  version) cat VERSION ;;
  clean) rm -f bin/seed bin/moc src/asm/*.o *.elf; rm -rf /tmp/mot; echo "已清理" ;;
  *) echo "用法: mo {build|run|test|boot|fmt|size|info|version|clean} [参数]"; exit 1 ;;
esac
