    .include "consts.s"
##############################################################################
#  lex.s -- 词法分析
##############################################################################
    .section .rodata
    .globl S_fn
S_fn: .ascii "fn\0"
    .globl S_var
S_var: .ascii "var\0"
    .globl S_let
S_let: .ascii "let\0"
    .globl S_if
S_if: .ascii "if\0"
    .globl S_else
S_else: .ascii "else\0"
    .globl S_while
S_while: .ascii "while\0"
    .globl S_break
    .globl E_BRK
E_BRK: .ascii "break outside of a loop\n"
    .globl E_CNT
E_CNT: .ascii "continue outside of a loop\n"
S_break: .ascii "break\0"
    .globl S_cont
S_cont: .ascii "continue\0"
    .globl S_return
S_return: .ascii "return\0"
    .globl S_i64
S_i64: .ascii "i64\0"
    .globl S_main
S_main: .ascii "main\0"
    .globl S_lp
S_lp: .ascii "(\0"
    .globl S_rp
S_rp: .ascii ")\0"
    .globl S_lb
S_lb: .ascii "{\0"
    .globl S_rb
S_rb: .ascii "}\0"
    .globl S_comma
S_comma: .ascii ",\0"
    .globl S_semi
S_semi: .ascii ";\0"
    .globl S_colon
S_colon: .ascii ":\0"
    .globl S_eq
S_eq: .ascii "=\0"
    .globl S_arrow
S_arrow: .ascii "->\0"
    .globl S_eqeq
S_eqeq: .ascii "==\0"
    .globl S_ne
S_ne: .ascii "!=\0"
    .globl S_le
S_le: .ascii "<=\0"
    .globl S_ge
S_ge: .ascii ">=\0"
    .globl S_andand
S_andand: .ascii "&&\0"
    .globl S_oror
S_oror: .ascii "||\0"
    .globl S_shl
S_shl: .ascii "<<\0"
    .globl S_shr
S_shr: .ascii ">>\0"
    .globl S_lt
S_lt: .ascii "<\0"
    .globl S_gt
S_gt: .ascii ">\0"
    .globl S_plus
S_plus: .ascii "+\0"
    .globl S_minus
S_minus: .ascii "-\0"
    .globl S_star
S_star: .ascii "*\0"
    .globl S_slash
S_slash: .ascii "/\0"
    .globl S_pct
S_pct: .ascii "%\0"
    .globl S_amp
S_amp: .ascii "&\0"
    .globl S_pipe
S_pipe: .ascii "|\0"
    .globl S_caret
S_caret: .ascii "^\0"
    .globl S_tilde
S_tilde: .ascii "~\0"
    .globl S_bang
S_bang: .ascii "!\0"

# 内建名
    .globl B_load8
B_load8: .ascii "load8\0"
    .globl B_load64
B_load64: .ascii "load64\0"
    .globl B_store8
B_store8: .ascii "store8\0"
    .globl B_store64
B_store64: .ascii "store64\0"
    .globl B_syscall
B_syscall: .ascii "syscall\0"
    .globl B_argc
B_argc: .ascii "argc\0"
    .globl B_argv
B_argv: .ascii "argv\0"

    .text

##############################################################################
#  syntax_error()
##############################################################################
    .globl syntax_error
syntax_error:
    leaq E_SYNTAX(%rip), %rdi
    movq $20, %rsi
    call die
    ret

##############################################################################
#  next_token()
##############################################################################
    .globl next_token
next_token:
.Lskip:
    movq pos(%rip), %r8
    movq %r8, tok_pos(%rip)
    movq srclen(%rip), %r9
    cmpq %r9, %r8
    jae .Leof
    leaq srcbuf(%rip), %r10
    movb (%r10,%r8), %al
    # 空白
    cmpb $32, %al
    je .Lws
    cmpb $9, %al
    je .Lws
    cmpb $10, %al
    je .Lws
    cmpb $13, %al
    je .Lws
    cmpb $35, %al          # '#'
    je .Lcomment
    jmp .Lclassify
.Lws:
    incq %r8
    movq %r8, pos(%rip)
    jmp .Lskip
.Lcomment:
    incq %r8
.Lcomment1:
    cmpq %r9, %r8
    jae .Leof2
    movb (%r10,%r8), %al
    incq %r8
    cmpb $10, %al
    je .Lskip2
    jmp .Lcomment1
.Lskip2:
    movq %r8, pos(%rip)
    jmp .Lskip
.Leof2:
    movq %r8, pos(%rip)
    jmp .Leof
.Leof:
    movq $0, tok_kind(%rip)
    ret

.Lclassify:
    call is_alpha
    testq %rax, %rax
    jnz .Lident
    movq pos(%rip), %r8
    leaq srcbuf(%rip), %r10
    movb (%r10,%r8), %al
    cmpb $95, %al          # '_'
    je .Lident
    # 数字
    cmpb $48, %al
    jb .Lnotdig
    cmpb $57, %al
    ja .Lnotdig
    jmp .Lnumber
.Lnotdig:
    # 字符串
    cmpb $34, %al
    je .Lstring
    # 字符字面量 'a'
    cmpb $39, %al
    je .Lchar
    jmp .Lpunct

# ---------------------------------------------------------------- 标识符
.Lident:
    movq pos(%rip), %r8
    leaq srcbuf(%rip), %r10
    leaq tokbuf(%rip), %r11
    xorq %rcx, %rcx
.Lident1:
    movb (%r10,%r8), %al
    movb %al, (%r11,%rcx)
    incq %r8
    incq %rcx
    movb (%r10,%r8), %al
    call is_alnum
    testq %rax, %rax
    jnz .Lident1
    cmpb $95, %al
    je .Lident1
    movb $0, (%r11,%rcx)
    movq %r8, pos(%rip)
    movq $1, tok_kind(%rip)
    ret

# ---------------------------------------------------------------- 字符字面量
#  'a' / '\n' / '\t' / '\r' / '\0' / '\\' / '\'' —— 值就是一个整数
.Lchar:
    incq %r8                       # 吃掉开头的引号
    movb (%r10,%r8), %al
    movzbq %al, %rax               # 零扩展：字符值
    cmpb $92, %al                  # '\'
    jne .Lch_done
    incq %r8
    movb (%r10,%r8), %al
    cmpb $110, %al                 # n
    je .Lch_n
    cmpb $116, %al                 # t
    je .Lch_t
    cmpb $114, %al                 # r
    je .Lch_r
    cmpb $48, %al                  # 0
    je .Lch_z
    jmp .Lch_raw                   # 其余（\\ \' "）原样
.Lch_n:
    movq $10, %rax
    jmp .Lch_done
.Lch_t:
    movq $9, %rax
    jmp .Lch_done
.Lch_r:
    movq $13, %rax
    jmp .Lch_done
.Lch_z:
    xorq %rax, %rax
    jmp .Lch_done
.Lch_raw:
    movzbq %al, %rax
.Lch_done:
    incq %r8                       # 吃掉字符本身
    # 判断闭合引号必须用另一个寄存器：%al 里现在是字符值，
    # 再往 %al 里读一个字节就会把它冲掉（曾导致 'm' 解析成 39）
    movb (%r10,%r8), %r11b
    cmpb $39, %r11b
    jne .Lch_store
    incq %r8
.Lch_store:
    movq %r8, pos(%rip)
    movq $2, tok_kind(%rip)
    andq $255, %rax
    movq %rax, tok_ival(%rip)
    leaq tokbuf(%rip), %r11
    movb $0, (%r11)
    ret

# ---------------------------------------------------------------- 数字
.Lnumber:
    xorq %r11, %r11
    movb (%r10,%r8), %al
    cmpb $48, %al
    jne .Ldec
    movb 1(%r10,%r8), %cl
    cmpb $120, %cl         # 'x'
    je .Lhex
    cmpb $88, %cl          # 'X'
    je .Lhex
.Ldec:
    xorq %r11, %r11
.Ldec1:
    movb (%r10,%r8), %al
    cmpb $48, %al
    jb .Ldec_done
    cmpb $57, %al
    ja .Ldec_done
    imulq $10, %r11
    movzbq %al, %rax
    subq $48, %rax
    addq %rax, %r11
    incq %r8
    jmp .Ldec1
.Ldec_done:
    jmp .Lnum_done
.Lhex:
    addq $2, %r8
    xorq %r11, %r11
.Lhex1:
    movb (%r10,%r8), %al
    call hexval
    cmpq $-1, %rax
    je .Lnum_done
    shlq $4, %r11
    addq %rax, %r11
    incq %r8
    jmp .Lhex1
.Lnum_done:
    movq %r8, pos(%rip)
    movq $2, tok_kind(%rip)
    movq %r11, tok_ival(%rip)
    leaq tokbuf(%rip), %r11
    movb $0, (%r11)
    ret

# ---------------------------------------------------------------- 字符串
#  内容直接写入 databuf，tok_ival = 数据段绝对地址
.Lstring:
    incq %r8                   # 跳过开引号
    movq data_len(%rip), %r11
    addq $DATA_VADDR, %r11     # 绝对地址
.Lstr1:
    movq srclen(%rip), %r9
    cmpq %r9, %r8
    jae .Lstr_end
    movb (%r10,%r8), %al
    cmpb $34, %al
    je .Lstr_end
    cmpb $92, %al              # '\'
    je .Lstr_esc
    movq %rax, %rdi
    andq $255, %rdi
    pushq %r8
    pushq %r10
    call dbyte
    popq %r10
    popq %r8
    incq %r8
    jmp .Lstr1
.Lstr_esc:
    incq %r8
    movb (%r10,%r8), %al
    incq %r8
    cmpb $110, %al             # n
    je .Lesc_n
    cmpb $116, %al             # t
    je .Lesc_t
    cmpb $114, %al             # r
    je .Lesc_r
    cmpb $48, %al              # 0
    je .Lesc_z
    cmpb $92, %al              # backslash
    je .Lesc_b
    cmpb $34, %al              # quote
    je .Lesc_b
    cmpb $39, %al              # '
    je .Lesc_b
    jmp .Lesc_b                # 默认原样
.Lesc_n:
    pushq %r8
    pushq %r10
    movq $10, %rdi
    call dbyte
    popq %r10
    popq %r8
    jmp .Lstr1
.Lesc_t:
    pushq %r8
    pushq %r10
    movq $9, %rdi
    call dbyte
    popq %r10
    popq %r8
    jmp .Lstr1
.Lesc_r:
    pushq %r8
    pushq %r10
    movq $13, %rdi
    call dbyte
    popq %r10
    popq %r8
    jmp .Lstr1
.Lesc_z:
    pushq %r8
    pushq %r10
    movq $0, %rdi
    call dbyte
    popq %r10
    popq %r8
    jmp .Lstr1
.Lesc_b:
    movzbq %al, %rdi
    pushq %r8
    pushq %r10
    call dbyte
    popq %r10
    popq %r8
    jmp .Lstr1
.Lstr_end:
    incq %r8                   # 跳过闭引号
    pushq %r8
    movq $0, %rdi
    call dbyte
    popq %r8
    movq %r8, pos(%rip)
    movq $3, tok_kind(%rip)
    movq %r11, tok_ival(%rip)
    leaq tokbuf(%rip), %r11
    movb $0, (%r11)
    ret

# ---------------------------------------------------------------- 标点
.Lpunct:
    leaq tokbuf(%rip), %r11
    movb (%r10,%r8), %al
    movb 1(%r10,%r8), %cl
    # 双字符
    cmpb $61, %al              # '='
    jne .Lp2
    cmpb $61, %cl
    jne .Lp2
    movw $0x3d3d, (%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp2:
    cmpb $33, %al              # '!'
    jne .Lp3
    cmpb $61, %cl
    jne .Lp3
    movb $33, (%r11)
    movb $61, 1(%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp3:
    cmpb $60, %al              # '<'
    jne .Lp4
    cmpb $61, %cl
    jne .Lp4a
    movb $60, (%r11)
    movb $61, 1(%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp4a:
    cmpb $60, %cl
    jne .Lp4
    movb $60, (%r11)
    movb $60, 1(%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp4:
    cmpb $62, %al              # '>'
    jne .Lp5
    cmpb $61, %cl
    jne .Lp5a
    movb $62, (%r11)
    movb $61, 1(%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp5a:
    cmpb $62, %cl
    jne .Lp5
    movb $62, (%r11)
    movb $62, 1(%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp5:
    cmpb $38, %al              # '&'
    jne .Lp6
    cmpb $38, %cl
    jne .Lp6
    movb $38, (%r11)
    movb $38, 1(%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp6:
    cmpb $124, %al             # '|'
    jne .Lp7
    cmpb $124, %cl
    jne .Lp7
    movb $124, (%r11)
    movb $124, 1(%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp7:
    cmpb $45, %al              # '-'
    jne .Lp8
    cmpb $62, %cl
    jne .Lp8
    movb $45, (%r11)
    movb $62, 1(%r11)
    movb $0, 2(%r11)
    addq $2, %r8
    jmp .Lp_done
.Lp8:
    # 单字符
    movb %al, (%r11)
    movb $0, 1(%r11)
    incq %r8
.Lp_done:
    movq %r8, pos(%rip)
    movq $4, tok_kind(%rip)
    ret

##############################################################################
#  辅助
##############################################################################
#  is_alpha(al)->rax
    .globl is_alpha
is_alpha:
    movzbq %al, %rax
    cmpq $97, %rax
    jb .Lia1
    cmpq $122, %rax
    ja .Lia1
    movq $1, %rax
    ret
.Lia1:
    cmpq $65, %rax
    jb .Lia_no
    cmpq $90, %rax
    ja .Lia_no
    movq $1, %rax
    ret
.Lia_no:
    xorq %rax, %rax
    ret

#  is_alnum(al)->rax
    .globl is_alnum
is_alnum:
    movzbq %al, %rax
    cmpq $48, %rax
    jb .Lian_a
    cmpq $57, %rax
    jbe .Lian_yes
.Lian_a:
    cmpq $65, %rax
    jb .Lian_b
    cmpq $90, %rax
    jbe .Lian_yes
.Lian_b:
    cmpq $97, %rax
    jb .Lian_c
    cmpq $122, %rax
    jbe .Lian_yes
.Lian_c:
    cmpq $95, %rax
    je .Lian_yes
    xorq %rax, %rax
    ret
.Lian_yes:
    movq $1, %rax
    ret

#  hexval(al)->rax (-1 非 hex)
    .globl hexval
hexval:
    movzbq %al, %rax
    cmpq $48, %rax
    jb .Lhv_no
    cmpq $57, %rax
    jbe .Lhv_d
    cmpq $97, %rax
    jb .Lhv_A
    cmpq $102, %rax
    ja .Lhv_no
    subq $87, %rax
    ret
.Lhv_A:
    cmpq $65, %rax
    jb .Lhv_no
    cmpq $70, %rax
    ja .Lhv_no
    subq $55, %rax
    ret
.Lhv_d:
    subq $48, %rax
    ret
.Lhv_no:
    movq $-1, %rax
    ret

##############################################################################
#  tok_is(rsi=常量串指针) -> rax
##############################################################################
    .globl tok_is
tok_is:
    movq tok_kind(%rip), %rax
    testq %rax, %rax
    jz .Lti_no
    leaq tokbuf(%rip), %rdi
    call streq
    ret
.Lti_no:
    xorq %rax, %rax
    ret

#  tok_is_name(rsi) : kind==1 且匹配
    .globl tok_is_name
tok_is_name:
    movq tok_kind(%rip), %rax
    cmpq $1, %rax
    jne .Lti_no
    leaq tokbuf(%rip), %rdi
    call streq
    ret

#  accept(rsi) -> rax 1/0，匹配则前进
    .globl accept
accept:
    pushq %r12
    movq %rsi, %r12
    call tok_is
    testq %rax, %rax
    jz .Lacc_no
    movq %r12, %rsi
    pushq %rsi
    call next_token
    popq %rsi
    popq %r12
    movq $1, %rax
    ret
.Lacc_no:
    popq %r12
    xorq %rax, %rax
    ret

#  expect(rsi)
    .globl expect
expect:
    pushq %r12
    movq %rsi, %r12
    call tok_is
    testq %rax, %rax
    jnz .Lexp_ok
    call syntax_error
.Lexp_ok:
    movq %r12, %rsi
    popq %r12
    call next_token
    ret

#  expect_ident() -> 要求 kind==1，返回 tokbuf 指针（拷贝前由调用方处理）
    .globl expect_ident
expect_ident:
    movq tok_kind(%rip), %rax
    cmpq $1, %rax
    je .Lei_ok
    call syntax_error
.Lei_ok:
    leaq tokbuf(%rip), %rax
    pushq %rax
    call next_token
    popq %rax
    ret

#  get_pos()->rax
    .globl get_pos
get_pos:
    movq pos(%rip), %rax
    ret

#  set_pos(rdi)
    .globl set_pos
set_pos:
    movq %rdi, pos(%rip)
    jmp next_token
