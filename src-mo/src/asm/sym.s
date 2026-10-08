    .include "consts.s"
##############################################################################
#  sym.s -- 符号表
#   kind: 0=函数 1=局部变量 2=全局变量
##############################################################################
    .text

# ---------------------------------------------------------------- sym_add
#  rdi=name_ptr rsi=kind rdx=addr rcx=npar -> rax=index
    .globl sym_add
sym_add:
    movq nsym(%rip), %rax
    pushq %rax                 # 保存 index
    pushq %rsi
    pushq %rdx
    pushq %rcx
    call intern                # rdi = name -> rax = namebuf 偏移
    popq %rcx
    popq %rdx
    popq %rsi
    popq %r8                   # r8 = index
    movq %rax, %r11            # r11 = name 偏移
    leaq sym_name(%rip), %r9
    movq %r11, (%r9,%r8,8)
    leaq sym_kind(%rip), %r9
    movq %rsi, (%r9,%r8,8)
    leaq sym_addr(%rip), %r9
    movq %rdx, (%r9,%r8,8)
    leaq sym_npar(%rip), %r9
    movq %rcx, (%r9,%r8,8)
    leaq sym_depth(%rip), %r9
    movq cur_depth(%rip), %r10
    movq %r10, (%r9,%r8,8)
    incq %r8
    movq %r8, nsym(%rip)
    decq %r8
    movq %r8, %rax
    ret

# ---------------------------------------------------------------- sym_lookup
#  rdi=name_ptr -> rax=index 或 -1  (查变量：局部+全局)
    .globl sym_lookup
sym_lookup:
    pushq %r12
    movq nsym(%rip), %r8
    testq %r8, %r8
    jz .Lsl_no
    decq %r8
.Lsl1:
    leaq sym_kind(%rip), %r9
    movq (%r9,%r8,8), %r10
    testq %r10, %r10
    jz .Lsl_next          # kind 0 是函数，跳过
    leaq sym_name(%rip), %r9
    movq (%r9,%r8,8), %r11
    leaq namebuf(%rip), %r12
    leaq (%r12,%r11), %rsi
    pushq %r8
    pushq %rdi
    call streq
    popq %rdi
    popq %r8
    testq %rax, %rax
    jnz .Lsl_yes
.Lsl_next:
    testq %r8, %r8
    jz .Lsl_no
    decq %r8
    jmp .Lsl1
.Lsl_yes:
    movq %r8, %rax
    popq %r12
    ret
.Lsl_no:
    movq $-1, %rax
    popq %r12
    ret

# ---------------------------------------------------------------- sym_lookup_func
#  rdi=name_ptr -> rax=index 或 -1
    .globl sym_lookup_func
sym_lookup_func:
    pushq %r12
    movq nsym(%rip), %r8
    testq %r8, %r8
    jz .Lsf_no
    decq %r8
.Lsf1:
    leaq sym_kind(%rip), %r9
    movq (%r9,%r8,8), %r10
    testq %r10, %r10
    jnz .Lsf_next
    leaq sym_name(%rip), %r9
    movq (%r9,%r8,8), %r11
    leaq namebuf(%rip), %r12
    leaq (%r12,%r11), %rsi
    pushq %r8
    pushq %rdi
    call streq
    popq %rdi
    popq %r8
    testq %rax, %rax
    jnz .Lsf_yes
.Lsf_next:
    testq %r8, %r8
    jz .Lsf_no
    decq %r8
    jmp .Lsf1
.Lsf_yes:
    movq %r8, %rax
    popq %r12
    ret
.Lsf_no:
    movq $-1, %rax
    popq %r12
    ret

# ---------------------------------------------------------------- sym_pop_scope
#  rdi=depth : 弹出 depth > rdi 的符号
    .globl sym_pop_scope
sym_pop_scope:
    movq nsym(%rip), %r8
    testq %r8, %r8
    jz .Lsp_done
.Lsp1:
    movq %r8, %rax
    decq %rax
    leaq sym_depth(%rip), %r9
    movq (%r9,%rax,8), %r10
    cmpq %rdi, %r10
    jb .Lsp_stop
    movq %rax, %r8
    testq %r8, %r8
    jnz .Lsp1
.Lsp_stop:
    movq %r8, nsym(%rip)
.Lsp_done:
    ret

# ---------------------------------------------------------------- sym_addr_of(rdi=index)->rax
    .globl sym_addr_of
sym_addr_of:
    leaq sym_addr(%rip), %r9
    movq (%r9,%rdi,8), %rax
    ret

# ---------------------------------------------------------------- sym_kind_of(rdi=index)->rax
    .globl sym_kind_of
sym_kind_of:
    leaq sym_kind(%rip), %r9
    movq (%r9,%rdi,8), %rax
    ret

# ---------------------------------------------------------------- sym_name_of(rdi=index)->rax 指针
    .globl sym_name_of
sym_name_of:
    leaq sym_name(%rip), %r9
    movq (%r9,%rdi,8), %r8
    leaq namebuf(%rip), %rax
    addq %r8, %rax
    ret
