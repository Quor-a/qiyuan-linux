    .include "consts.s"
##############################################################################
#  expr.s -- 表达式解析 + x86-64 代码生成（结果一律留在 rax）
#   栈约定（parse_primary）：(%rsp)[0..255] 名字缓冲, 256(%rsp) nargs, 264(%rsp) sym
##############################################################################
    .section .rodata
U_UNDEF: .ascii "error: undefined symbol: \0"

    .text

# ---------------------------------------------------------------- err_undef(rdi=name)
    .globl err_undef
err_undef:
    movq %rdi, %r12
    movq $1, %rax
    movq $2, %rdi
    leaq U_UNDEF(%rip), %rsi
    movq $25, %rdx
    syscall
    movq %r12, %rdi
    call strlen
    movq %rax, %rdx
    movq $1, %rax
    movq $2, %rdi
    movq %r12, %rsi
    syscall
    movq $1, %rax
    movq $2, %rdi
    leaq E_NL(%rip), %rsi
    movq $1, %rdx
    syscall
    movq $60, %rax
    movq $1, %rdi
    syscall
    ret

# ---------------------------------------------------------------- g_lnot : rax = !rax
    .globl g_lnot
g_lnot:
    call g_cmp_rax_0
    movb $0x0f, %dil
    call emit1
    movb $0x94, %dil
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

    .globl g_zero_rax
g_zero_rax:
    movb $0x31, %dil
    call emit1
    movb $0xc0, %dil
    call emit1
    ret

##############################################################################
    .globl parse_expr
parse_expr:
    jmp parse_or

##############################################################################
#  ||
##############################################################################
    .globl parse_or
parse_or:
    pushq %rbx
    subq $16, %rsp
    call parse_and
.Lor1:
    leaq S_oror(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jz .Lor_done
    call next_token
    call new_label
    movq %rax, (%rsp)          # Ltrue
    call new_label
    movq %rax, 8(%rsp)         # Lend
    call g_cmp_rax_0
    movq $0x85, %rdi           # jne
    movq (%rsp), %rsi
    call emit_jcc
    call parse_and
    call g_cmp_rax_0
    movq $0x85, %rdi
    movq (%rsp), %rsi
    call emit_jcc
    xorq %rdi, %rdi
    call g_movabs_rax          # 0
    movq 8(%rsp), %rdi
    call emit_jmp
    movq (%rsp), %rdi
    call place_label
    movq $1, %rdi
    call g_movabs_rax          # 1
    movq 8(%rsp), %rdi
    call place_label
    jmp .Lor1
.Lor_done:
    addq $16, %rsp
    popq %rbx
    ret

##############################################################################
#  &&
##############################################################################
    .globl parse_and
parse_and:
    pushq %rbx
    subq $16, %rsp
    call parse_bor
.Land1:
    leaq S_andand(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jz .Land_done
    call next_token
    call new_label
    movq %rax, (%rsp)          # Lfalse
    call new_label
    movq %rax, 8(%rsp)         # Lend
    call g_cmp_rax_0
    movq $0x84, %rdi           # je
    movq (%rsp), %rsi
    call emit_jcc
    call parse_bor
    call g_cmp_rax_0
    movq $0x84, %rdi
    movq (%rsp), %rsi
    call emit_jcc
    movq $1, %rdi
    call g_movabs_rax
    movq 8(%rsp), %rdi
    call emit_jmp
    movq (%rsp), %rdi
    call place_label
    xorq %rdi, %rdi
    call g_movabs_rax
    movq 8(%rsp), %rdi
    call place_label
    jmp .Land1
.Land_done:
    addq $16, %rsp
    popq %rbx
    ret

##############################################################################
#  逐层二元
##############################################################################
    .globl parse_bor
parse_bor:
    pushq %rbx
    call parse_bxor
.Lbor1:
    leaq S_pipe(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jz .Lbor_done
    call next_token
    call g_push_rax
    call parse_bxor
    call g_pop_rcx
    call g_or
    jmp .Lbor1
.Lbor_done:
    popq %rbx
    ret

    .globl parse_bxor
parse_bxor:
    pushq %rbx
    call parse_band
.Lbx1:
    leaq S_caret(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jz .Lbx_done
    call next_token
    call g_push_rax
    call parse_band
    call g_pop_rcx
    call g_xor
    jmp .Lbx1
.Lbx_done:
    popq %rbx
    ret

    .globl parse_band
parse_band:
    pushq %rbx
    call parse_eq
.Lba1:
    leaq S_amp(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jz .Lba_done
    call next_token
    call g_push_rax
    call parse_eq
    call g_pop_rcx
    call g_and
    jmp .Lba1
.Lba_done:
    popq %rbx
    ret

    .globl parse_eq
parse_eq:
    pushq %rbx
    pushq %r12
    subq $16, %rsp
    call parse_rel
.Leq1:
    leaq S_eqeq(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Leq_eq
    leaq S_ne(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Leq_ne
    jmp .Leq_done
.Leq_eq:
    movq $0x94, (%rsp)
    jmp .Leq_go
.Leq_ne:
    movq $0x95, (%rsp)
.Leq_go:
    call next_token
    call g_push_rax
    call parse_rel
    call g_pop_rcx
    movq (%rsp), %rdi
    call g_cmp_set
    jmp .Leq1
.Leq_done:
    addq $16, %rsp
    popq %r12
    popq %rbx
    ret

    .globl parse_rel
parse_rel:
    pushq %rbx
    pushq %r12
    subq $16, %rsp
    call parse_shift
.Lrel1:
    leaq S_lt(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lrel_lt
    leaq S_le(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lrel_le
    leaq S_gt(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lrel_gt
    leaq S_ge(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lrel_ge
    jmp .Lrel_done
.Lrel_lt:
    movq $0x9c, (%rsp)
    jmp .Lrel_go
.Lrel_le:
    movq $0x9e, (%rsp)
    jmp .Lrel_go
.Lrel_gt:
    movq $0x9f, (%rsp)
    jmp .Lrel_go
.Lrel_ge:
    movq $0x9d, (%rsp)
.Lrel_go:
    call next_token
    call g_push_rax
    call parse_shift
    call g_pop_rcx
    movq (%rsp), %rdi
    call g_cmp_set
    jmp .Lrel1
.Lrel_done:
    addq $16, %rsp
    popq %r12
    popq %rbx
    ret

    .globl parse_shift
parse_shift:
    pushq %rbx
    call parse_add
.Lsh1:
    leaq S_shl(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lsh_shl
    leaq S_shr(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lsh_shr
    jmp .Lsh_done
.Lsh_shl:
    call next_token
    call g_push_rax
    call parse_add
    call g_pop_rcx
    call g_shl
    jmp .Lsh1
.Lsh_shr:
    call next_token
    call g_push_rax
    call parse_add
    call g_pop_rcx
    call g_sar
    jmp .Lsh1
.Lsh_done:
    popq %rbx
    ret

    .globl parse_add
parse_add:
    pushq %rbx
    call parse_mul
.Ladd1:
    leaq S_plus(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Ladd_p
    leaq S_minus(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Ladd_m
    jmp .Ladd_done
.Ladd_p:
    call next_token
    call g_push_rax
    call parse_mul
    call g_pop_rcx
    call g_add_rax_rcx
    jmp .Ladd1
.Ladd_m:
    call next_token
    call g_push_rax
    call parse_mul
    call g_pop_rcx
    call g_sub
    jmp .Ladd1
.Ladd_done:
    popq %rbx
    ret

    .globl parse_mul
parse_mul:
    pushq %rbx
    call parse_unary
.Lmul1:
    leaq S_star(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lmul_s
    leaq S_slash(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lmul_d
    leaq S_pct(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lmul_r
    jmp .Lmul_done
.Lmul_s:
    call next_token
    call g_push_rax
    call parse_unary
    call g_pop_rcx
    call g_imul
    jmp .Lmul1
.Lmul_d:
    call next_token
    call g_push_rax
    call parse_unary
    call g_pop_rcx
    call g_div
    jmp .Lmul1
.Lmul_r:
    call next_token
    call g_push_rax
    call parse_unary
    call g_pop_rcx
    call g_mod
    jmp .Lmul1
.Lmul_done:
    popq %rbx
    ret

##############################################################################
    .globl parse_unary
parse_unary:
    leaq S_minus(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lu_neg
    leaq S_tilde(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lu_not
    leaq S_bang(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lu_lnot
    jmp parse_primary
.Lu_neg:
    call next_token
    call parse_unary
    call g_neg_rax
    ret
.Lu_not:
    call next_token
    call parse_unary
    call g_not_rax
    ret
.Lu_lnot:
    call next_token
    call parse_unary
    call g_lnot
    ret

##############################################################################
#  parse_primary
##############################################################################
    .globl parse_primary
parse_primary:
    subq $288, %rsp
    movq tok_kind(%rip), %rax
    cmpq $2, %rax
    je .Lp_int
    cmpq $3, %rax
    je .Lp_str
    cmpq $1, %rax
    je .Lp_name
    cmpq $4, %rax
    je .Lp_punct
    call syntax_error
.Lp_int:
    movq tok_ival(%rip), %rdi
    call g_movabs_rax
    call next_token
    addq $288, %rsp
    ret
.Lp_str:
    movq tok_ival(%rip), %rdi
    call g_movabs_rax
    call next_token
    addq $288, %rsp
    ret
.Lp_punct:
    leaq S_lp(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lp_paren
    call syntax_error
.Lp_paren:
    call next_token
    call parse_expr
    leaq S_rp(%rip), %rsi
    call expect
    addq $288, %rsp
    ret

.Lp_name:
    leaq tokbuf(%rip), %rsi
    leaq (%rsp), %rdi
    call memcpy_ex
    call next_token
    leaq S_lp(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lp_call
    leaq (%rsp), %rdi
    call sym_lookup
    cmpq $-1, %rax
    je .Lp_undef
    movq %rax, 264(%rsp)
    movq %rax, %rdi
    call sym_kind_of
    cmpq $1, %rax
    je .Lp_local
    movq 264(%rsp), %rdi
    call sym_addr_of
    movq %rax, %rdi
    call g_load_global
    jmp .Lp_vdone
.Lp_local:
    movq 264(%rsp), %rdi
    call sym_addr_of
    movq %rax, %rdi
    call g_load_local
.Lp_vdone:
    addq $288, %rsp
    ret
.Lp_undef:
    leaq (%rsp), %rdi
    call err_undef

.Lp_call:
    call next_token
    movq $0, 256(%rsp)         # nargs
    leaq S_rp(%rip), %rsi
    call tok_is
    testq %rax, %rax
    jnz .Lp_args_done
.Lp_arg1:
    call parse_expr
    call g_push_rax
    movq 256(%rsp), %rax
    incq %rax
    movq %rax, 256(%rsp)
    leaq S_comma(%rip), %rsi
    call accept
    testq %rax, %rax
    jnz .Lp_arg1
.Lp_args_done:
    leaq S_rp(%rip), %rsi
    call expect
    leaq (%rsp), %rdi
    leaq B_load8(%rip), %rsi
    call streq
    testq %rax, %rax
    jnz .Lb_load8
    leaq (%rsp), %rdi
    leaq B_load64(%rip), %rsi
    call streq
    testq %rax, %rax
    jnz .Lb_load64
    leaq (%rsp), %rdi
    leaq B_store8(%rip), %rsi
    call streq
    testq %rax, %rax
    jnz .Lb_store8
    leaq (%rsp), %rdi
    leaq B_store64(%rip), %rsi
    call streq
    testq %rax, %rax
    jnz .Lb_store64
    leaq (%rsp), %rdi
    leaq B_argc(%rip), %rsi
    call streq
    testq %rax, %rax
    jnz .Lb_argc
    leaq (%rsp), %rdi
    leaq B_argv(%rip), %rsi
    call streq
    testq %rax, %rax
    jnz .Lb_argv
    leaq (%rsp), %rdi
    leaq B_syscall(%rip), %rsi
    call streq
    testq %rax, %rax
    jnz .Lb_syscall
    jmp .Lp_regular

.Lb_argc:
    # rax = [0x10000000]
    movq $0x10000000, %rdi
    call g_movabs_rax
    movb $0x48, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    movb $0x00, %dil
    call emit1
    jmp .Lp_calldone
.Lb_argv:
    # rax = [[0x10000000+8] + rax*8]
    call g_pop_rax
    # rax *= 8 -> shl rax,3（4 字节，比 imul 的 6 字节短）
    movb $0x48, %dil
    call emit1
    movb $0xc1, %dil
    call emit1
    movb $0xe0, %dil
    call emit1
    movb $0x03, %dil
    call emit1
    call g_push_rax
    movq $0x10000008, %rdi
    call g_movabs_rax
    movb $0x48, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    movb $0x00, %dil
    call emit1
    call g_pop_rcx
    movb $0x48, %dil
    call emit1
    movb $0x01, %dil
    call emit1
    movb $0xc8, %dil
    call emit1
    movb $0x48, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    movb $0x00, %dil
    call emit1
    jmp .Lp_calldone

.Lb_load8:
    call g_pop_rax
    movb $0x0f, %dil
    call emit1
    movb $0xb6, %dil
    call emit1
    movb $0x00, %dil
    call emit1
    jmp .Lp_calldone
.Lb_load64:
    call g_pop_rax
    movb $0x48, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    movb $0x00, %dil
    call emit1
    jmp .Lp_calldone
.Lb_store8:
    call g_pop_rbx             # rbx = val
    call g_pop_rcx             # rcx = addr
    movb $0x88, %dil           # mov [rcx], bl
    call emit1
    movb $0x19, %dil
    call emit1
    call g_zero_rax
    jmp .Lp_calldone
.Lb_store64:
    call g_pop_rbx
    call g_pop_rcx
    movb $0x48, %dil           # mov [rcx], rbx
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0x19, %dil
    call emit1
    call g_zero_rax
    jmp .Lp_calldone

.Lb_syscall:
    movq 256(%rsp), %rax
    cmpq $7, %rax
    jb .Lsy6
    call g_pop_r9
.Lsy6:
    movq 256(%rsp), %rax
    cmpq $6, %rax
    jb .Lsy5
    call g_pop_r8
.Lsy5:
    movq 256(%rsp), %rax
    cmpq $5, %rax
    jb .Lsy4
    call g_pop_r10
.Lsy4:
    movq 256(%rsp), %rax
    cmpq $4, %rax
    jb .Lsy3
    call g_pop_rdx
.Lsy3:
    movq 256(%rsp), %rax
    cmpq $3, %rax
    jb .Lsy2
    call g_pop_rsi
.Lsy2:
    movq 256(%rsp), %rax
    cmpq $2, %rax
    jb .Lsy1
    call g_pop_rdi
.Lsy1:
    call g_pop_rax
    call g_syscall
    jmp .Lp_calldone

.Lp_regular:
    movq 256(%rsp), %rax
    cmpq $6, %rax
    jb .Lr5
    call g_pop_r9
.Lr5:
    movq 256(%rsp), %rax
    cmpq $5, %rax
    jb .Lr4
    call g_pop_r8
.Lr4:
    movq 256(%rsp), %rax
    cmpq $4, %rax
    jb .Lr3
    call g_pop_rcx
.Lr3:
    movq 256(%rsp), %rax
    cmpq $3, %rax
    jb .Lr2
    call g_pop_rdx
.Lr2:
    movq 256(%rsp), %rax
    cmpq $2, %rax
    jb .Lr1
    call g_pop_rsi
.Lr1:
    movq 256(%rsp), %rax
    cmpq $1, %rax
    jb .Lr0
    call g_pop_rdi
.Lr0:
    leaq (%rsp), %rdi
    call sym_lookup_func
    cmpq $-1, %rax
    je .Lp_undef
    movq %rax, %rdi
    call emit_call_patch
    jmp .Lp_calldone

.Lp_calldone:
    addq $288, %rsp
    ret

# ---------------------------------------------------------------- memcpy_ex(d,s)
    .globl memcpy_ex
memcpy_ex:
    xorq %rax, %rax
.Lme1:
    movb (%rsi,%rax), %cl
    movb %cl, (%rdi,%rax)
    testb %cl, %cl
    jz .Lme2
    incq %rax
    jmp .Lme1
.Lme2:
    ret
