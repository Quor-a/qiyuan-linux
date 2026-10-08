    .include "consts.s"
##############################################################################
#  main.s -- 入口：读源码、编译、回填、输出 ELF64 静态可执行文件
##############################################################################
    .section .data
    .globl outname, elfhdr
outname:  .quad 0
elfhdr:   .space 176
zerobuf:  .space 4096
    .globl seg1_size
seg1_size: .quad 0
dbgbuf:   .space 64
    .globl main_patch
main_patch: .quad 0

    .section .rodata
M_OUT:    .ascii ".out\0"

    .globl dbgmsg
dbgmsg:   .ascii " ns\n"
    .globl dbgspc
dbgspc:   .ascii " "

    .text
    .globl _start
_start:
    movq (%rsp), %rax
    cmpq $3, %rax
    jae .Largc_ok
    leaq E_NOSRC(%rip), %rdi
    movq $30, %rsi
    call die
.Largc_ok:
    movq 16(%rsp), %rdi          # argv[1] 输入
    call open_read
    movq 24(%rsp), %rax          # argv[2] 输出
    movq %rax, outname(%rip)
    call emit_startup
    # 数据段头 16 字节留给 argc/argv
    xorq %rdi, %rdi
    call dquad
    xorq %rdi, %rdi
    call dquad
    call parse_program
    call resolve_all

    leaq S_main(%rip), %rdi
    call sym_lookup_func
    cmpq $-1, %rax
    jne .Lgot_main
    leaq E_NOMAIN(%rip), %rdi
    movq $21, %rsi
    call die
.Lgot_main:
    movq %rax, %rdi
    call sym_addr_of
    movq %rax, %r12
    leaq codebuf(%rip), %r8
    movq main_patch(%rip), %r9
    movq %r12, (%r8,%r9)
    movq $CODE_VADDR, %rax
    addq $CODE_OFF, %rax
    movq %rax, entry_addr(%rip)
    call build_elf
call write_out
    movq $60, %rax
    xorq %rdi, %rdi
    syscall

# ---------------------------------------------------------------- print_num(rdi)
    .globl print_num
print_num:
    leaq dbgbuf(%rip), %r8
    movq %rdi, %rax
    movq $10, %r13
    xorq %r9, %r9
.Lpn1:
    xorq %rdx, %rdx
    divq %r13
    addb $48, %dl
    movb %dl, (%r8,%r9)
    incq %r9
    testq %rax, %rax
    jnz .Lpn1
    movq %r9, %r10
    xorq %r11, %r11
.Lpn2:
    decq %r10
    cmpq %r11, %r10
    jbe .Lpn3
    movb (%r8,%r10), %cl
    movb (%r8,%r11), %dl
    movb %cl, (%r8,%r11)
    movb %dl, (%r8,%r10)
    incq %r11
    jmp .Lpn2
.Lpn3:
    movq %r8, %rsi
    movq %r9, %rdx
    movq $1, %rax
    movq $2, %rdi
    syscall
    movq $1, %rax
    movq $2, %rdi
    leaq dbgspc(%rip), %rsi
    movq $1, %rdx
    syscall
    ret

# ---------------------------------------------------------------- writestr(rdi,rsi)
    .globl writestr
writestr:
    movq %rsi, %rdx
    movq %rdi, %rsi
    movq $2, %rdi
    movq $1, %rax
    syscall
    ret

##############################################################################
#  emit_startup : 在代码缓冲开头生成 _start（call main; exit(rax)）
##############################################################################
    .globl emit_startup
emit_startup:
    # 把 argc / argv 存进数据段头：rax=[rsp] -> [0x10000000], lea rcx,[rsp+8] -> [0x10000008]
    # mov rax, [rsp]              48 8b 04 24
    movb $0x48, %dil
    call emit1
    movb $0x8b, %dil
    call emit1
    movb $0x04, %dil
    call emit1
    movb $0x24, %dil
    call emit1
    # movabs r11, 0x10000000      49 bb imm64
    movb $0x49, %dil
    call emit1
    movb $0xbb, %dil
    call emit1
    movq $0x10000000, %rdi
    call emit8
    # mov [r11], rax              49 89 03
    movb $0x49, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0x03, %dil
    call emit1
    # lea rcx, [rsp+8]            48 8d 4c 24 08
    movb $0x48, %dil
    call emit1
    movb $0x8d, %dil
    call emit1
    movb $0x4c, %dil
    call emit1
    movb $0x24, %dil
    call emit1
    movb $0x08, %dil
    call emit1
    # mov [r11+8], rcx            49 89 4b 08
    movb $0x49, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0x4b, %dil
    call emit1
    movb $0x08, %dil
    call emit1
    # movabs rax, imm64   (main 地址，稍后回填)
    movb $0x48, %dil
    call emit1
    movb $0xb8, %dil
    call emit1
    movq code_len(%rip), %rax
    movq %rax, main_patch(%rip)
    xorq %rdi, %rdi
    call emit8
    # call rax
    call spill_cache
    movb $0xff, %dil
    call emit1
    movb $0xd0, %dil
    call emit1
    # mov rdi, rax
    movb $0x48, %dil
    call emit1
    movb $0x89, %dil
    call emit1
    movb $0xc7, %dil
    call emit1
    # mov rax, 60
    movb $0x48, %dil
    call emit1
    movb $0xc7, %dil
    call emit1
    movb $0xc0, %dil
    call emit1
    movl $60, %edi
    call emit4
    # syscall
    movb $0x0f, %dil
    call emit1
    movb $0x05, %dil
    call emit1
    ret

##############################################################################
#  open_read(rdi=path)
##############################################################################
    .globl open_read
open_read:
    movq %rdi, %r12
    movq $2, %rax                # sys_open
    xorq %rsi, %rsi
    xorq %rdx, %rdx
    syscall
    testq %rax, %rax
    jns .Lor_ok
    leaq E_OPENIN(%rip), %rdi
    movq $25, %rsi
    call die
.Lor_ok:
    movq %rax, %r13              # fd
    movq $0, %rax                # sys_read
    movq %r13, %rdi
    leaq srcbuf(%rip), %rsi
    movq $SRC_CAP, %rdx
    syscall
    movq %rax, srclen(%rip)
    movq $3, %rax                # sys_close
    movq %r13, %rdi
    syscall
    movq $0, pos(%rip)
    ret

##############################################################################
#  resolve_all : 回填函数地址与跳转偏移
##############################################################################
    .globl resolve_all
resolve_all:
    # --- 函数地址 ---
    movq nfnp(%rip), %r10
    testq %r10, %r10
    jz .Lra_jmp
    xorq %r11, %r11
.Lra1:
    leaq fnp_sym(%rip), %r8
    movq (%r8,%r11,8), %rdi      # sym index
    leaq sym_addr(%rip), %r9
    movq (%r9,%rdi,8), %rdx      # 绝对地址
    leaq fnp_pos(%rip), %r8
    movq (%r8,%r11,8), %r9       # codebuf 偏移
    leaq codebuf(%rip), %r12
    movq %rdx, (%r12,%r9)
    incq %r11
    cmpq %r10, %r11
    jne .Lra1
    # --- 跳转 ---
.Lra_jmp:
    movq njmp(%rip), %r10
    testq %r10, %r10
    jz .Lra_done
    xorq %r11, %r11
.Lra2:
    leaq jmp_lab(%rip), %r8
    movq (%r8,%r11,8), %rdi
    leaq labels(%rip), %r9
    movq (%r9,%rdi,8), %rdx      # 目标偏移
    leaq jmp_pos(%rip), %r8
    movq (%r8,%r11,8), %r9       # rel32 所在偏移
    # rel32 = target - (pos + 4)
    movq %rdx, %rax
    subq %r9, %rax
    subq $4, %rax
    leaq codebuf(%rip), %r12
    movl %eax, (%r12,%r9)
    incq %r11
    cmpq %r10, %r11
    jne .Lra2
.Lra_done:
    ret

##############################################################################
#  build_elf
##############################################################################
    .globl build_elf
build_elf:
    leaq elfhdr(%rip), %r8
    # 清零
    xorq %rax, %rax
.Lbe_zero:
    movq $0, (%r8,%rax)
    addq $8, %rax
    cmpq $176, %rax
    jne .Lbe_zero
    # e_ident
    movb $0x7f, (%r8)
    movb $0x45, 1(%r8)
    movb $0x4c, 2(%r8)
    movb $0x46, 3(%r8)
    movb $2, 4(%r8)
    movb $1, 5(%r8)
    movb $1, 6(%r8)
    # e_type / e_machine / e_version
    movw $2, 16(%r8)
    movw $0x3e, 18(%r8)
    movl $1, 20(%r8)
    # e_entry
    movq entry_addr(%rip), %rax
    movq %rax, 24(%r8)
    # e_phoff
    movq $64, 32(%r8)
    # e_ehsize / e_phentsize / e_phnum
    movw $64, 52(%r8)
    movw $56, 54(%r8)
    movw $2, 56(%r8)
    # seg1 大小
    movq code_len(%rip), %rax
    addq $176, %rax
    addq $4095, %rax
    andq $-4096, %rax
    movq %rax, seg1_size(%rip)
    # --- PH1 ---
    leaq 64(%r8), %r9
    movl $1, (%r9)
    movl $5, 4(%r9)              # R|X
    movq $0, 8(%r9)              # p_offset
    movq $CODE_VADDR, 16(%r9)    # p_vaddr
    movq $CODE_VADDR, 24(%r9)    # p_paddr
    movq %rax, 32(%r9)           # p_filesz
    movq %rax, 40(%r9)           # p_memsz
    movq $4096, 48(%r9)
    # --- PH2 ---
    leaq 120(%r8), %r9
    movl $1, (%r9)
    movl $6, 4(%r9)              # R|W
    movq seg1_size(%rip), %rax
    movq %rax, 8(%r9)            # p_offset
    movq $DATA_VADDR, 16(%r9)
    movq $DATA_VADDR, 24(%r9)
    movq data_len(%rip), %rax
    movq %rax, 32(%r9)
    movq %rax, 40(%r9)
    movq $4096, 48(%r9)
    ret

##############################################################################
#  write_out
##############################################################################
    .globl write_out
write_out:
    movq $2, %rax                # sys_open
    movq outname(%rip), %rdi
    movq $0x241, %rsi            # O_WRONLY|O_CREAT|O_TRUNC
    movq $0x1ed, %rdx            # 0755
    syscall
    testq %rax, %rax
    jns .Lwo_ok
    leaq E_OPENOUT(%rip), %rdi
    movq $26, %rsi
    call die
.Lwo_ok:
    movq %rax, %r12              # fd
    # header
    movq $1, %rax
    movq %r12, %rdi
    leaq elfhdr(%rip), %rsi
    movq $176, %rdx
    syscall
    # code
    movq $1, %rax
    movq %r12, %rdi
    leaq codebuf(%rip), %rsi
    movq code_len(%rip), %rdx
    syscall
    # padding
    movq code_len(%rip), %rax
    addq $176, %rax
    movq %rax, %rcx
    andq $4095, %rcx
    jz .Lwo_nopad
    movq $4096, %rdx
    subq %rcx, %rdx
    movq %rdx, %r13
    movq $1, %rax
    movq %r12, %rdi
    leaq zerobuf(%rip), %rsi
    syscall
.Lwo_nopad:
    # data
    movq $1, %rax
    movq %r12, %rdi
    leaq databuf(%rip), %rsi
    movq data_len(%rip), %rdx
    syscall
    # close
    movq $3, %rax
    movq %r12, %rdi
    syscall
    ret
