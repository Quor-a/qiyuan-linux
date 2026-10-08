    .include "consts.s"
##############################################################################
#  base.s -- 墨语言 seed 编译器：数据段、基础工具、字节发射、x86-64 指令发射
#  调用约定（seed 内部）：参数 rdi/rsi/rdx，返回 rax，
#                        破坏 rax/rcx/rdx/rsi/rdi/r8-r11，保持 rbx/rbp/r12-r15
##############################################################################

    .set CODE_VADDR,  0x400000
    .set CODE_OFF,    176          # 64(ELF头) + 2*56(程序头)
    .set DATA_VADDR,  0x10000000

    .set SRC_CAP,     4194304      # 4MB 源码缓冲
    .set CODE_CAP,    1048576      # 1MB 生成代码
    .set DATA_CAP,    1048576      # 1MB 数据段
    .set NAME_CAP,    262144       # 256KB 符号名池
    .set NSYM_MAX,    2048
    .set NPATCH_MAX,  16384
    .set NLAB_MAX,    4096

##############################################################################
#  数据段
##############################################################################
    .section .data

    .globl srcbuf
srcbuf:      .space SRC_CAP
    .globl codebuf
codebuf:     .space CODE_CAP
    .globl databuf
databuf:     .space DATA_CAP
    .globl namebuf
namebuf:     .space NAME_CAP

    .globl tokbuf
tokbuf:      .space 256

# --- 源码扫描状态 ---
    .globl srclen, pos, tok_pos
srclen:      .quad 0
pos:         .quad 0
tok_pos:     .quad 0

# --- 输出缓冲长度 ---
    .globl code_len, data_len, name_len
code_len:    .quad 0
data_len:    .quad 0
name_len:    .quad 0

# --- 当前 token ---
    .globl tok_kind, tok_ival
tok_kind:    .quad 0        # 0=EOF 1=名字 2=整数 3=字符串 4=标点
tok_ival:    .quad 0

# --- 符号表 ---
    .globl sym_name, sym_kind, sym_addr, sym_npar, sym_depth, nsym
sym_name:    .space NSYM_MAX*8     # namebuf 内偏移
sym_kind:    .space NSYM_MAX*8     # 0=函数 1=局部 2=全局
sym_addr:    .space NSYM_MAX*8
sym_npar:    .space NSYM_MAX*8
sym_depth:   .space NSYM_MAX*8
nsym:        .quad 0

    .globl cur_depth
cur_depth:   .quad 0

# --- 函数地址回填表 ---
    .globl fnp_pos, fnp_sym, nfnp
fnp_pos:     .space NPATCH_MAX*8
fnp_sym:     .space NPATCH_MAX*8
nfnp:        .quad 0

# --- 跳转回填表 ---
    .globl jmp_pos, jmp_lab, njmp
jmp_pos:     .space NPATCH_MAX*8
jmp_lab:     .space NPATCH_MAX*8
njmp:        .quad 0

# --- 标签表 ---
    .globl labels, nlab
labels:      .space NLAB_MAX*8
nlab:        .quad 0

# --- 杂项 ---
    .globl tmp_a, tmp_b
tmp_a:       .quad 0
tmp_b:       .quad 0
    .globl ltop, lstk
ltop:        .quad 0
lstk:        .space 512
    .globl pjmp, pjlbl, pjend
pjmp:        .quad 0      # 上一条 jmp 在跳转表里的下标+1；0 表示没有待删的死跳转
pjlbl:       .quad 0
pjend:       .quad 0
    .globl last, lastv, lastr
last:        .quad 0      # 0=无 1=rax 里是刚发的 imm32 常量 2=rax 里是刚发的 [rbp+off]
lastv:       .quad 0
crbx:        .quad 0      # rbx 里是否缓存着「最后一次 push」的值
lastr:       .quad 0      # 折叠时需要回退的字节数
    .globl pl, plv, plr
pl:          .quad 0      # 上一次 pop rcx 时右操作数是否为常量
plv:         .quad 0
plr:         .quad 0

    .globl cur_fn_off        # 当前函数的栈帧大小
cur_fn_off:  .quad 0
    .globl last_expr_void
last_expr_void: .quad 0
    .globl entry_addr
entry_addr:  .quad 0

##############################################################################
#  只读数据
##############################################################################
    .section .rodata
ARG_MODRM: .byte 0x7d, 0x75, 0x55, 0x4d, 0x45, 0x4d
ARG_REX:   .byte 0x48, 0x48, 0x48, 0x48, 0x4c, 0x4c

    .globl E_NOSRC
E_NOSRC: .ascii "usage: seed <input.mo> <output>\n"
    .globl E_OPENIN
E_OPENIN: .ascii "error: cannot open input\n"
    .globl E_OPENOUT
E_OPENOUT: .ascii "error: cannot open output\n"
    .globl E_SYNTAX
E_SYNTAX: .ascii "error: syntax error\n"
    .globl E_NOMAIN
E_NOMAIN: .ascii "error: no main function\n"
    .globl E_UNDEF
E_UNDEF: .ascii "error: undefined symbol: "
    .globl E_REDEF
E_REDEF: .ascii "error: duplicate symbol: "
    .globl E_BIG
E_BIG: .ascii "error: buffer overflow\n"
    .globl E_NL
E_NL: .ascii "\n"

##############################################################################
#  基础工具
##############################################################################
    .text

# ---------------------------------------------------------------- die(msg,len)
    .globl die
die:
    movq %rsi, %rdx          # len
    movq %rdi, %rsi          # buf
    movq $2, %rdi            # stderr
    movq $1, %rax            # sys_write
    syscall
    movq $60, %rax
    movq $1, %rdi
    syscall
    ret

# ---------------------------------------------------------------- diez(msg NUL结尾)
    .globl diez
diez:
    pushq %rdi
    call strlen
    movq %rax, %rsi
    popq %rdi
    call die

# ---------------------------------------------------------------- strlen(s)->rax
    .globl strlen
strlen:
    xorq %rax, %rax
.Lstrlen1:
    cmpb $0, (%rdi,%rax)
    je .Lstrlen2
    incq %rax
    jmp .Lstrlen1
.Lstrlen2:
    ret

# ---------------------------------------------------------------- streq(a,b)->rax(1/0)
    .globl streq
streq:
    xorq %rax, %rax
.Lstreq1:
    movb (%rdi,%rax), %cl
    cmpb %cl, (%rsi,%rax)
    jne .Lstreq_no
    cmpb $0, %cl
    je .Lstreq_yes
    incq %rax
    jmp .Lstreq1
.Lstreq_yes:
    movq $1, %rax
    ret
.Lstreq_no:
    xorq %rax, %rax
    ret

# ---------------------------------------------------------------- memcpy(d,s,n)
#  rdi=dest rsi=src rdx=n
    .globl memcpy
memcpy:
    testq %rdx, %rdx
    jz .Lmemcpy_done
    xorq %rax, %rax
.Lmemcpy1:
    movb (%rsi,%rax), %cl
    movb %cl, (%rdi,%rax)
    incq %rax
    cmpq %rdx, %rax
    jne .Lmemcpy1
.Lmemcpy_done:
    ret

# ---------------------------------------------------------------- 发射字节到代码缓冲
#  emit1(dil)
    .globl emit1
emit1:
    movq $0, last(%rip)
    movq $0, pjmp(%rip)
    leaq codebuf(%rip), %r8
    movq code_len(%rip), %r9
    cmpq $CODE_CAP, %r9
    jae .Lovf
    movb %dil, (%r8,%r9)
    incq %r9
    movq %r9, code_len(%rip)
    ret

#  emit4(edi)
    .globl emit4
emit4:
    movq $0, last(%rip)
    leaq codebuf(%rip), %r8
    movq code_len(%rip), %r9
    cmpq $CODE_CAP, %r9
    jae .Lovf
    movl %edi, (%r8,%r9)
    addq $4, %r9
    movq %r9, code_len(%rip)
    ret

#  emit8(rdi)
    .globl emit8
emit8:
    movq $0, last(%rip)
    leaq codebuf(%rip), %r8
    movq code_len(%rip), %r9
    cmpq $CODE_CAP, %r9
    jae .Lovf
    movq %rdi, (%r8,%r9)
    addq $8, %r9
    movq %r9, code_len(%rip)
    ret

.Lovf:
    leaq E_BIG(%rip), %rdi
    movq $24, %rsi
    call die

# ---------------------------------------------------------------- 发射字节到数据缓冲
#  dbyte(dil)
    .globl dbyte
dbyte:
    leaq databuf(%rip), %r8
    movq data_len(%rip), %r9
    cmpq $DATA_CAP, %r9
    jae .Lovf
    movb %dil, (%r8,%r9)
    incq %r9
    movq %r9, data_len(%rip)
    ret

#  dquad(rdi)
    .globl dquad
dquad:
    leaq databuf(%rip), %r8
    movq data_len(%rip), %r9
    movq %rdi, (%r8,%r9)
    addq $8, %r9
    movq %r9, data_len(%rip)
    ret

# ---------------------------------------------------------------- 符号名池
#  intern(s)->rax : 把 NUL 结尾字符串拷入 namebuf，返回偏移
    .globl intern
intern:
    movq %rdi, %r8           # src
    leaq namebuf(%rip), %r9
    movq name_len(%rip), %r10
    movq %r10, %rax          # 返回偏移
.Lintern1:
    movb (%r8), %cl
    movb %cl, (%r9,%r10)
    incq %r8
    incq %r10
    cmpb $0, %cl
    jne .Lintern1
    movq %r10, name_len(%rip)
    ret

# ---------------------------------------------------------------- 标签管理
#  new_label()->rax
    .globl new_label
new_label:
    movq nlab(%rip), %rax
    incq %rax
    movq %rax, nlab(%rip)
    decq %rax
    ret

#  place_label(id)
    .globl place_label
place_label:
    movq pjmp(%rip), %r10
    testq %r10, %r10
    jz .Lpl_plain
    movq pjlbl(%rip), %r11
    cmpq %r11, %rdi
    jne .Lpl_plain
    movq pjend(%rip), %r11
    movq code_len(%rip), %r9
    cmpq %r11, %r9
    jne .Lpl_plain
    # 删除死 jmp：回退 5 字节
    movq %r11, %r9
    subq $5, %r9
    movq %r9, code_len(%rip)
    decq %r10
    movq %r10, njmp(%rip)
    movq $0, pjmp(%rip)
    # 同步已落在 old 处的标签（如 if 的 else 标签）
    leaq labels(%rip), %r8
    movq nlab(%rip), %rcx
.Lpl_fix:
    testq %rcx, %rcx
    jz .Lpl_plain
    decq %rcx
    movq (%r8,%rcx,8), %rax
    cmpq %r11, %rax
    jne .Lpl_fix
    movq %r9, (%r8,%rcx,8)
    jmp .Lpl_fix
.Lpl_plain:
    leaq labels(%rip), %r8
    movq code_len(%rip), %r9
    movq %r9, (%r8,%rdi,8)
    ret

# ---------------------------------------------------------------- 跳转发射
#  Jcc/Jmp 条件码(用于 0F 8x)
#  emit_jcc(rdi=cc字节, rsi=label)
    .globl emit_jcc
emit_jcc:
    movq %rdi, tmp_b(%rip)
    movq %rsi, tmp_a(%rip)
    movb $0x0f, %dil
    call emit1
    movq tmp_b(%rip), %rdi
    call emit1
    # 记录 patch 位置
    movq njmp(%rip), %r10
    leaq jmp_pos(%rip), %r8
    movq code_len(%rip), %r9
    movq %r9, (%r8,%r10,8)
    leaq jmp_lab(%rip), %r8
    movq tmp_a(%rip), %rax
    movq %rax, (%r8,%r10,8)
    incq %r10
    movq %r10, njmp(%rip)
    # 发射 4 字节占位
    xorq %rdi, %rdi
    call emit4
    ret

#  emit_jmp(rsi=label)  -> E9 rel32
    .globl emit_jmp
emit_jmp:
    movq %rdi, tmp_a(%rip)
    movb $0xe9, %dil
    call emit1
    movq njmp(%rip), %r10
    leaq jmp_pos(%rip), %r8
    movq code_len(%rip), %r9
    movq %r9, (%r8,%r10,8)
    leaq jmp_lab(%rip), %r8
    movq tmp_a(%rip), %rax
    movq %rax, (%r8,%r10,8)
    incq %r10
    movq %r10, njmp(%rip)
    xorq %rdi, %rdi
    call emit4
    # 记录待删死跳转（必须在 emit4 之后，emit1/emit4 会清标记）
    movq njmp(%rip), %r10
    movq %r10, pjmp(%rip)
    movq tmp_a(%rip), %rax
    movq %rax, pjlbl(%rip)
    movq code_len(%rip), %rax
    movq %rax, pjend(%rip)
    ret

# ---------------------------------------------------------------- 函数地址回填
#  emit_call_patch(rdi=sym_index)
#   发射 movabs rax,imm64 ; call rax，并记录 imm64 位置用于回填
    .globl emit_call_patch
emit_call_patch:
    movq %rdi, tmp_a(%rip)
    movb $0x48, %dil
    call emit1
    movb $0xb8, %dil
    call emit1
    # 记录
    movq nfnp(%rip), %r10
    leaq fnp_pos(%rip), %r8
    movq code_len(%rip), %r9
    movq %r9, (%r8,%r10,8)
    leaq fnp_sym(%rip), %r8
    movq tmp_a(%rip), %rax
    movq %rax, (%r8,%r10,8)
    incq %r10
    movq %r10, nfnp(%rip)
    xorq %rdi, %rdi
    call emit8
    call spill_cache
    movb $0xff, %dil
    call emit1
    movb $0xd0, %dil
    call emit1
    ret

#  emit_movabs_r11(rdi=addr)  49 BB imm64
    .globl emit_movabs_r11
emit_movabs_r11:
    movq %rdi, tmp_a(%rip)
    movb $0x49, %dil
    call emit1
    movb $0xbb, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit8
    ret

# ---------------------------------------------------------------- emit_store_arg
#  rdi=栈槽偏移(0..255) rsi=参数序号(0..5)
#  mov [rbp+off], <argreg>
    .globl emit_store_arg
emit_store_arg:
    movq %rdi, tmp_a(%rip)          # off
    movq %rsi, tmp_b(%rip)          # i
    cmpq $6, %rsi
    jae .Lsa_stack
    # 寄存器参数（前 6 个）
    leaq ARG_REX(%rip), %r8
    movb (%r8,%rsi,1), %dil
    call emit1
    movb $0x89, %dil
    call emit1
    leaq ARG_MODRM(%rip), %r8
    movq tmp_b(%rip), %rsi
    movb (%r8,%rsi,1), %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit1
    ret
.Lsa_stack:
    # 第 7 个起在调用者压的栈上：arg[i] 在 [rbp + 16 + (na-1-i)*8]
    pushq %r12
    movq %rdx, %r12                 # na
    subq $1, %r12
    subq %rsi, %r12                 # na-1-i
    imulq $8, %r12
    addq $16, %r12                  # disp
    # mov rax, [rbp + disp]
    movb $0x48, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    cmpq $127, %r12
    jg .Lsa_d32
    movb $0x45, %dil
    call emit1
    movq %r12, %rdi
    andq $255, %rdi
    call emit1
    jmp .Lsa_st
.Lsa_d32:
    movb $0x85, %dil
    call emit1
    movq %r12, %rdi
    call emit4
.Lsa_st:
    # mov [rbp+off], rax
    movq tmp_a(%rip), %r12          # off（负数）
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    cmpq $-128, %r12
    jl .Lsa_o32
    movb $0x45, %dil
    call emit1
    movq %r12, %rdi
    andq $255, %rdi
    call emit1
    popq %r12
    ret
.Lsa_o32:
    movb $0x85, %dil
    call emit1
    movq %r12, %rdi
    call emit4
    popq %r12
    ret

##############################################################################
#  生成代码用的 x86-64 指令发射器（发射到 codebuf）
##############################################################################

#  g_push_rax   50
    .globl g_push_rax
g_push_rax:
    movq last(%rip), %rax
    movq $0, last(%rip)
    cmpq $1, %rax
    je .Lpsh_imm
    cmpq $2, %rax
    je .Lpsh_loc
    call spill_cache
    call cache_rbx
    ret
.Lpsh_imm:
    movq lastv(%rip), %r8
    # 回退 mov eax,imm32 的 5 字节
    movq lastr(%rip), %r9
    subq %r9, code_len(%rip)
    cmpq $127, %r8
    jg .Lpsh_imm32
    call spill_cache
    movb $0x6a, %dil
    call emit1
    movq lastv(%rip), %rdi
    andq $255, %rdi
    call emit1
    ret
.Lpsh_imm32:
    # push imm32 会符号扩展，常量 >= 2^31 时与 mov eax,imm32（零扩展）不等价
    cmpq $2147483647, %r8
    jg .Lpsh_plain2
    call spill_cache
    movb $0x68, %dil
    call emit1
    movq lastv(%rip), %rdi
    call emit4
    ret
.Lpsh_plain2:
    # 无法折叠：把刚才回退的字节加回来，再发 push rax
    movq lastr(%rip), %r9
    addq %r9, code_len(%rip)
    call spill_cache
    call cache_rbx
    ret
.Lpsh_loc:
    movq lastr(%rip), %r9
    subq %r9, code_len(%rip)
    movq lastv(%rip), %r8
    cmpq $-128, %r8
    jl .Lpsh_loc32
    cmpq $127, %r8
    jg .Lpsh_loc32
    call spill_cache
    movb $0xff, %dil
    call emit1
    movb $0x75, %dil
    call emit1
    movq lastv(%rip), %rdi
    andq $255, %rdi
    call emit1
    ret
.Lpsh_loc32:
    call spill_cache
    movb $0xff, %dil
    call emit1
    movb $0xb5, %dil
    call emit1
    movq lastv(%rip), %rdi
    call emit4
    ret

#  try_fold_rhs: 右操作数是编译期常量时回退它的 mov eax,imm32
#    返回 rax=1（已回退，常量在 plv），0（不可折叠）
#    上限 2^31-1：立即数形式做符号扩展，超过就与 mov eax,imm32 的零扩展不等价
    .globl try_fold_rhs
try_fold_rhs:
    movq pl(%rip), %rax
    testq %rax, %rax
    jz .Ltfr_no
    movq $2147483647, %r9
    cmpq %r9, plv(%rip)
    jg .Ltfr_no
    movq $0, pl(%rip)
    movq plr(%rip), %r9
    subq %r9, code_len(%rip)
    subq $1, code_len(%rip)
    movq $1, %rax
    ret
.Ltfr_no:
    movq $0, pl(%rip)
    xorq %rax, %rax
    ret

#  emit_g1_imm(rdi=imm8 的 modrm, rsi=imm32 的操作码)：rax <op>= plv
    .globl emit_g1_imm
emit_g1_imm:
    movq %rdi, tmp_a(%rip)
    movq %rsi, tmp_b(%rip)
    movq plv(%rip), %r8
    cmpq $127, %r8
    jg .Leg32
    movb $0x48, %dil
    call emit1
    movb $0x83, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit1
    movq plv(%rip), %rdi
    andq $255, %rdi
    call emit1
    ret
.Leg32:
    movb $0x48, %dil
    call emit1
    movq tmp_b(%rip), %rdi
    call emit1
    movq plv(%rip), %rdi
    call emit4
    ret

#  loop_push(rdi=continue 标签, rsi=break 标签)
    .globl loop_push
loop_push:
    pushq %r8
    pushq %r9
    movq ltop(%rip), %r8
    leaq lstk(%rip), %r9
    movq %rdi, (%r9,%r8,8)
    movq %rsi, 8(%r9,%r8,8)
    addq $2, %r8
    movq %r8, ltop(%rip)
    popq %r9
    popq %r8
    ret

#  loop_pop: 退出一层循环
    .globl loop_pop
loop_pop:
    pushq %r8
    movq ltop(%rip), %r8
    subq $2, %r8
    movq %r8, ltop(%rip)
    popq %r8
    ret

#  loop_cnt -> rax 当前 continue 标签；不在循环里返回 -1
    .globl loop_cnt
loop_cnt:
    pushq %r8
    pushq %r9
    movq ltop(%rip), %r8
    testq %r8, %r8
    jz .Llc_no
    subq $2, %r8
    leaq lstk(%rip), %r9
    movq (%r9,%r8,8), %rax
    popq %r9
    popq %r8
    ret
.Llc_no:
    movq $-1, %rax
    popq %r9
    popq %r8
    ret

#  loop_brk -> rax 当前 break 标签；不在循环里返回 -1
    .globl loop_brk
loop_brk:
    pushq %r8
    pushq %r9
    movq ltop(%rip), %r8
    testq %r8, %r8
    jz .Llb_no
    subq $1, %r8
    leaq lstk(%rip), %r9
    movq (%r9,%r8,8), %rax
    popq %r9
    popq %r8
    ret
.Llb_no:
    movq $-1, %rax
    popq %r9
    popq %r8
    ret

#  g_pop_rcx    59
    .globl g_pop_rcx
g_pop_rcx:
    movq crbx(%rip), %rax
    testq %rax, %rax
    jz .Lprc_old
    movq $0, crbx(%rip)
    movq $0, pl(%rip)
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xd9, %dil
    call emit1
    ret
.Lprc_old:
    movq last(%rip), %rax
    cmpq $1, %rax
    jne .Lprc_no
    movq $1, pl(%rip)
    movq lastv(%rip), %r8
    movq %r8, plv(%rip)
    movq lastr(%rip), %r8
    movq %r8, plr(%rip)
    jmp .Lprc_emit
.Lprc_no:
    movq $0, pl(%rip)
.Lprc_emit:
    movb $0x59, %dil
    call emit1
    ret

#  g_pop_rbx    5B
    .globl g_pop_rbx
g_pop_rbx:
    call spill_cache
    movb $0x5b, %dil
    call emit1
    ret

#  g_pop_rax    58
    .globl g_pop_rax
g_pop_rax:
    call spill_cache
    movb $0x58, %dil
    call emit1
    ret

#  g_pop_rdi    5F
    .globl g_pop_rdi
g_pop_rdi:
    call spill_cache
    movb $0x5f, %dil
    call emit1
    ret

#  g_pop_rsi    5E
    .globl g_pop_rsi
g_pop_rsi:
    call spill_cache
    movb $0x5e, %dil
    call emit1
    ret

#  g_pop_rdx    5A
    .globl g_pop_rdx
g_pop_rdx:
    call spill_cache
    movb $0x5a, %dil
    call emit1
    ret

#  g_pop_rcx2   59  (参数用)
#  g_pop_r10    41 5A
    .globl g_pop_r10
g_pop_r10:
    call spill_cache
    movb $0x41, %dil
    call emit1
    movb $0x5a, %dil
    call emit1
    ret

#  g_pop_r8     41 58
    .globl g_pop_r8
g_pop_r8:
    call spill_cache
    movb $0x41, %dil
    call emit1
    movb $0x58, %dil
    call emit1
    ret

#  g_pop_r9     41 59
    .globl g_pop_r9
g_pop_r9:
    call spill_cache
    movb $0x41, %dil
    call emit1
    movb $0x59, %dil
    call emit1
    ret

#  spill_cache: 若 rbx 缓存着最后一次 push 的值，先把它落栈。
# 维持不变式 crbx==1 <=> 最后一次 push 在 rbx 里：
# 任何新的 push 之前必须先 spill，栈序才不会乱。
    .globl spill_cache
spill_cache:
    movq crbx(%rip), %rax
    testq %rax, %rax
    jz .Lsc_done
    movb $0x53, %dil
    call emit1
    movq $0, crbx(%rip)
.Lsc_done:
    ret

#  cache_rbx: mov rbx, rax（代替 push rax）
    .globl cache_rbx
cache_rbx:
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xc3, %dil
    call emit1
    movq $1, crbx(%rip)
    ret

#  g_mov_rbx_rax   48 89 C3
    .globl g_mov_rbx_rax
g_mov_rbx_rax:
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xc3, %dil
    call emit1
    ret

#  g_mov_rax_rcx   48 89 C8
    .globl g_mov_rax_rcx
g_mov_rax_rcx:
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xc8, %dil
    call emit1
    ret

#  g_add_rax_rcx  48 01 C8
    .globl g_add_rax_rcx
g_add_rax_rcx:
    call try_fold_rhs
    testq %rax, %rax
    jz .Lad_old
    movb $0x58, %dil
    call emit1
    movq $0xc0, %rdi
    movq $0x05, %rsi
    call emit_g1_imm
    ret
.Lad_old:
    movb $0x48, %dil
    call emit1
    movb $0x01, %dil
    call emit1
    movb $0xc8, %dil
    call emit1
    ret

#  g_sub:  rax = rcx - rax   ->  48 29 C1 ; 48 89 C8
    .globl g_sub
g_sub:
    movb $0x48, %dil
    call emit1
    movb $0x29, %dil
    call emit1
    movb $0xc1, %dil
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xc8, %dil
    call emit1
    ret

#  g_imul: rax = rcx * rax -> 48 0F AF C1
    .globl g_imul
g_imul:
    call try_fold_rhs
    testq %rax, %rax
    jz .Lim_old
    movb $0x58, %dil
    call emit1
    movq plv(%rip), %r8
    cmpq $127, %r8
    jg .Lim32
    movb $0x48, %dil
    call emit1
    movb $0x6b, %dil
    call emit1
    movb $0xc0, %dil
    call emit1
    movq plv(%rip), %rdi
    andq $255, %rdi
    call emit1
    ret
.Lim32:
    movb $0x48, %dil
    call emit1
    movb $0x69, %dil
    call emit1
    movb $0xc0, %dil
    call emit1
    movq plv(%rip), %rdi
    call emit4
    ret
.Lim_old:
    movb $0x48, %dil
    call emit1
    movb $0x0f, %dil
    call emit1
    movb $0xaf, %dil
    call emit1
    movb $0xc1, %dil
    call emit1
    ret

#  g_div: rax = rcx / rax (有符号)
    .globl g_div
g_div:
    # 除法用 rbx 当除数，先让缓存落栈，否则左操作数就丢了
    call spill_cache
    call g_mov_rbx_rax       # rbx = rhs
    call g_mov_rax_rcx       # rax = lhs
    movb $0x48, %dil
    call emit1
    movb $0x99, %dil         # cqto
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0xf7, %dil
    call emit1
    movb $0xfb, %dil         # idiv rbx
    call emit1
    ret

#  g_mod: rax = rcx % rax
    .globl g_mod
g_mod:
    call spill_cache
    call g_mov_rbx_rax
    call g_mov_rax_rcx
    movb $0x48, %dil
    call emit1
    movb $0x99, %dil
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0xf7, %dil
    call emit1
    movb $0xfb, %dil
    call emit1
    # mov rax, rdx : 48 89 D0
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xd0, %dil
    call emit1
    ret

#  g_and: rax = rcx & rax -> 48 21 C8
    .globl g_and
g_and:
    call try_fold_rhs
    testq %rax, %rax
    jz .Land_old
    movb $0x58, %dil
    call emit1
    movq $0xe0, %rdi
    movq $0x25, %rsi
    call emit_g1_imm
    ret
.Land_old:
    movb $0x48, %dil
    call emit1
    movb $0x21, %dil
    call emit1
    movb $0xc8, %dil
    call emit1
    ret

#  g_or: 48 09 C8
    .globl g_or
g_or:
    call try_fold_rhs
    testq %rax, %rax
    jz .Lor_old
    movb $0x58, %dil
    call emit1
    movq $0xc8, %rdi
    movq $0x0d, %rsi
    call emit_g1_imm
    ret
.Lor_old:
    movb $0x48, %dil
    call emit1
    movb $0x09, %dil
    call emit1
    movb $0xc8, %dil
    call emit1
    ret

#  g_xor: 48 31 C8
    .globl g_xor
g_xor:
    call try_fold_rhs
    testq %rax, %rax
    jz .Lxor_old
    movb $0x58, %dil
    call emit1
    movq $0xf0, %rdi
    movq $0x35, %rsi
    call emit_g1_imm
    ret
.Lxor_old:
    movb $0x48, %dil
    call emit1
    movb $0x31, %dil
    call emit1
    movb $0xc8, %dil
    call emit1
    ret

#  g_shl: rax = rcx << (rax&63)
    .globl g_shl
g_shl:
    call g_mov_rbx_rax       # rbx = rhs
    call g_mov_rax_rcx       # rax = lhs
    # mov rcx, rbx : 48 89 D9
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xd9, %dil
    call emit1
    # shl rax, cl : 48 D3 E0
    movb $0x48, %dil
    call emit1
    movb $0xd3, %dil
    call emit1
    movb $0xe0, %dil
    call emit1
    ret

#  g_sar: rax = rcx >> (rax&63) 算术
    .globl g_sar
g_sar:
    call g_mov_rbx_rax
    call g_mov_rax_rcx
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xd9, %dil
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0xd3, %dil
    call emit1
    movb $0xf8, %dil
    call emit1
    ret

#  g_cmp_set(rdi=setcc字节): 比较 rcx 与 rax，结果(0/1)放 rax
#   48 39 C1 (cmp rcx,rax) ; 0F 9x C0 ; 48 0F B6 C0
    .globl g_cmp_set
g_cmp_set:
    movq %rdi, tmp_a(%rip)
    call try_fold_rhs
    testq %rax, %rax
    jz .Lcs_old
    movb $0x59, %dil
    call emit1
    movq plv(%rip), %r8
    cmpq $127, %r8
    jg .Lcs32
    movb $0x48, %dil
    call emit1
    movb $0x83, %dil
    call emit1
    movb $0xf9, %dil
    call emit1
    movq plv(%rip), %rdi
    andq $255, %rdi
    call emit1
    jmp .Lcs_set
.Lcs32:
    movb $0x48, %dil
    call emit1
    movb $0x81, %dil
    call emit1
    movb $0xf9, %dil
    call emit1
    movq plv(%rip), %rdi
    call emit4
.Lcs_set:
    movb $0x0f, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit1
    movb $0xc0, %dil
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0x0f, %dil
    call emit1
    movb $0xb6, %dil
    call emit1
    movb $0xc0, %dil
    call emit1
    ret
.Lcs_old:
    movb $0x48, %dil
    call emit1
    movb $0x39, %dil
    call emit1
    movb $0xc1, %dil
    call emit1
    movb $0x0f, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit1
    movb $0xc0, %dil
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0x0f, %dil
    call emit1
    movb $0xb6, %dil
    call emit1
    movb $0xc0, %dil
    call emit1
    ret

#  g_cmp_rax_0: 48 83 F8 00
    .globl g_cmp_rax_0
g_cmp_rax_0:
    movb $0x48, %dil
    call emit1
    movb $0x83, %dil
    call emit1
    movb $0xf8, %dil
    call emit1
    movb $0x00, %dil
    call emit1
    ret

#  g_neg_rax: 48 F7 D8
    .globl g_neg_rax
g_neg_rax:
    movb $0x48, %dil
    call emit1
    movb $0xf7, %dil
    call emit1
    movb $0xd8, %dil
    call emit1
    ret

#  g_not_rax: 48 F7 D0
    .globl g_not_rax
g_not_rax:
    movb $0x48, %dil
    call emit1
    movb $0xf7, %dil
    call emit1
    movb $0xd0, %dil
    call emit1
    ret

#  g_load_local(rdi=off): mov rax, [rbp+off]
#    -128..127 -> 48 8B 45 disp8 (4 字节)；否则 48 8B 85 disp32 (7 字节)
#    与 compiler.mo 的 g_load_local 必须保持一致，否则自举会不一致
    .globl g_load_local
g_load_local:
    movq %rdi, tmp_a(%rip)
    cmpq $-128, %rdi
    jl .Lgll32
    cmpq $127, %rdi
    jg .Lgll32
    movb $0x48, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    movb $0x45, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    andq $255, %rdi
    call emit1
    movq $2, last(%rip)
    movq tmp_a(%rip), %rax
    movq %rax, lastv(%rip)
    movq $4, lastr(%rip)
    ret
.Lgll32:
    movb $0x48, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    movb $0x85, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit4
    movq $2, last(%rip)
    movq tmp_a(%rip), %rax
    movq %rax, lastv(%rip)
    movq $7, lastr(%rip)
    ret

#  g_store_local(rdi=off): mov [rbp+off], rax
    .globl g_store_local
g_store_local:
    movq %rdi, tmp_a(%rip)
    cmpq $-128, %rdi
    jl .Lgsl32
    cmpq $127, %rdi
    jg .Lgsl32
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0x45, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    andq $255, %rdi
    call emit1
    ret
.Lgsl32:
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0x85, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit4
    ret

#  g_load_arg(rdi=off): mov rax, [rbp+off] 与 local 同（off 为正）
#  g_load_global(rdi=vaddr): movabs r11,addr ; mov rax,[r11]
    .globl g_load_global
g_load_global:
    call emit_movabs_r11
    movb $0x49, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    movb $0x03, %dil
    call emit1
    ret

#  g_store_global(rdi=vaddr): movabs r11,addr ; mov [r11],rax
    .globl g_store_global
g_store_global:
    call emit_movabs_r11
    movb $0x49, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0x03, %dil
    call emit1
    ret

#  g_movabs_rax(rdi=imm)
#    0 <= imm < 2^32  ->  mov eax, imm32   (B8 imm32, 5 字节)
#    否则              ->  movabs rax, imm64 (48 B8 imm64, 10 字节)
#    与 compiler.mo 里的 g_movabs_rax 保持一致，否则自举会不一致
    .globl g_movabs_rax
g_movabs_rax:
    movq %rdi, tmp_a(%rip)
    testq %rdi, %rdi
    js .Lgmv_big
    movq $4294967295, %rax
    cmpq %rax, %rdi
    jg .Lgmv_big
    movb $0xb8, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit4
    movq $1, last(%rip)
    movq tmp_a(%rip), %rax
    movq %rax, lastv(%rip)
    movq $5, lastr(%rip)
    ret
.Lgmv_big:
    movb $0x48, %dil
    call emit1
    movb $0xb8, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit8
    ret

#  g_syscall: 0F 05
    .globl g_syscall
g_syscall:
    movb $0x0f, %dil
    call emit1
    movb $0x05, %dil
    call emit1
    ret

#  g_prologue(rdi=frame): push rbp; mov rbp,rsp; sub rsp,frame
    .globl g_prologue
g_prologue:
    movq %rdi, tmp_a(%rip)
    movb $0x55, %dil
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xe5, %dil
    call emit1
    cmpq $0, tmp_a(%rip)
    je .Lpro_skip
    movb $0x48, %dil
    call emit1
    movb $0x81, %dil
    call emit1
    movb $0xec, %dil
    call emit1
    movq tmp_a(%rip), %rdi
    call emit4
.Lpro_skip:
    ret

#  g_epilogue: mov rsp,rbp; pop rbp; ret
    .globl g_epilogue
g_epilogue:
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xec, %dil
    call emit1
    movb $0x5d, %dil
    call emit1
    movb $0xc3, %dil
    call emit1
    ret

#  g_ret_0: xor eax,eax 然后 epilogue
