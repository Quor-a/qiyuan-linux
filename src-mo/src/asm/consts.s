# 常量（各文件共享）
.set CODE_VADDR,  0x400000
.set CODE_OFF,    176          # 64(ELF头) + 2*56(程序头)
.set DATA_VADDR,  0x10000000
.set SRC_CAP,     4194304      # 4MB 源码缓冲
.set CODE_CAP,    1048576      # 1MB 生成代码
.set DATA_CAP,    1048576      # 1MB 数据段
.set NAME_CAP,    262144       # 256KB 符号名池
.set NSYM_MAX,    1024
.set NPATCH_MAX,  16384
.set NLAB_MAX,    4096
