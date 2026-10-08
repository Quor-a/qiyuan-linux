# 墨语言构建入口
#
#   make          从汇编重建 seed，再编译出 moc
#   make test     跑全部测试
#   make boot     验证自举闭环
#   make all      上面三步
#   make clean    清掉产物

SEED := bin/seed
MOC  := bin/moc
ASM  := src/asm

.DEFAULT_GOAL := all

mo2x:
	./bin/moc tools/mo2x.mo bin/mo2x

.PHONY: all test boot clean check mo2x sync sync-check

all: sync-check $(MOC) boot test check

# ---------------------------------------------------------------------------
#  src/compiler.mo 是 src/mo/compiler_part{1..5}.mo 的**拼接产物**。
#  曾经出现过：只改了 compiler.mo，没同步回 src/mo/ ——
#  于是任何人执行文档里那句 cat 拼接，就会把修复静默还原。
#  这里用一条守护把这件事钉死：拼接结果必须与 compiler.mo 逐字节相同。
# ---------------------------------------------------------------------------
sync-check:
	@cat src/mo/compiler_part1.mo src/mo/compiler_part2.mo \
	     src/mo/compiler_part3.mo src/mo/compiler_part4.mo \
	     src/mo/compiler_part5.mo > /tmp/mo_joined.mo
	@if ! diff -q /tmp/mo_joined.mo src/compiler.mo >/dev/null; then \
	    echo "✗ src/mo/ 拼接结果与 src/compiler.mo 不一致。"; \
	    echo "  改编译器要改 src/mo/ 下的片段，然后 make sync 重新拼接。"; \
	    diff /tmp/mo_joined.mo src/compiler.mo | head -10; \
	    exit 1; \
	fi
	@echo "✓ 拼接一致"

sync:
	@cat src/mo/compiler_part1.mo src/mo/compiler_part2.mo \
	     src/mo/compiler_part3.mo src/mo/compiler_part4.mo \
	     src/mo/compiler_part5.mo > src/compiler.mo
	@echo "已重新拼接 src/compiler.mo"

# 额外自检：库依赖独立可编译 + 两个后端结果一致
check:
	@bash tools/projcheck.sh
	@bash tools/multibackend_test.sh

$(SEED): $(ASM)/base.s $(ASM)/lex.s $(ASM)/sym.s $(ASM)/expr.s $(ASM)/stmt.s $(ASM)/main.s
	@echo "== 汇编 seed =="
	cd $(ASM) && for f in base lex sym expr stmt main; do as -o $$f.o $$f.s; done
	cd $(ASM) && ld -o ../../$(SEED) base.o lex.o sym.o expr.o stmt.o main.o

$(MOC): $(SEED) src/compiler.mo
	@echo "== 用 seed 编译 compiler.mo =="
	./build.sh self $(SEED)

test: $(MOC)
	bash tests/run.sh $(MOC) | tail -3

boot: $(MOC)
	bash verify_bootstrap.sh

clean:
	rm -f $(SEED) $(MOC) $(ASM)/*.o
