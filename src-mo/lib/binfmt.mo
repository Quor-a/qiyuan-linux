# binfmt —— 魔数识别、版本与元数据读取（用墨语言自己写的）
#
# 「魔数」是文件开头的几个字节，用来判断它到底是什么格式。
# 这里做两件事：
#   1. 按魔数识别常见格式（ELF / gzip / tar / PNG / ZIP / PDF / 脚本 ...）
#   2. 读出 ELF 头里的「版本 / 架构 / 入口 / 节数」等元数据
#
# 全部只读前若干字节，纯计算，不需要任何库。

import "fs.mo";
import "str.mo";

var MAGIC: [512] byte = 0;

# 读文件前 n 字节到 MAGIC，返回实际读到的字节数
fn magic_load(path: i64, n: i64) -> i64 {
    return read_file(path, &MAGIC, n);
}

# 是否以某个字节序列开头（sig 是以 0 结尾的字节串）
fn starts_with(sig: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        if load8(&MAGIC + i) != load8(sig + i) { return 0; }
        i = i + 1;
    }
    return 1;
}

# 返回格式编号：0=未知 1=ELF 2=gzip 3=tar 4=PNG 5=ZIP 6=PDF
# 7=JPEG 8=BMP 9=WASM 10=脚本(shebang) 11=纯文本
fn magic_type() -> i64 {
    # ELF: 7f 45 4c 46
    if MAGIC[0] == 127 {
        if MAGIC[1] == 69 {
            if MAGIC[2] == 76 {
                if MAGIC[3] == 70 { return 1; }
            }
        }
    }
    # gzip: 1f 8b
    if MAGIC[0] == 31 {
        if MAGIC[1] == 139 { return 2; }
    }
    # WASM: 00 61 73 6d
    if MAGIC[0] == 0 {
        if MAGIC[1] == 97 {
            if MAGIC[2] == 115 {
                if MAGIC[3] == 109 { return 9; }
            }
        }
    }
    # PNG: 89 50 4e 47
    if MAGIC[0] == 137 {
        if MAGIC[1] == 80 {
            if MAGIC[2] == 78 {
                if MAGIC[3] == 71 { return 4; }
            }
        }
    }
    # PDF: %PDF
    if MAGIC[0] == 37 {
        if MAGIC[1] == 80 {
            if MAGIC[2] == 68 {
                if MAGIC[3] == 70 { return 6; }
            }
        }
    }
    # JPEG: ff d8 ff
    if MAGIC[0] == 255 {
        if MAGIC[1] == 216 {
            if MAGIC[2] == 255 { return 7; }
        }
    }
    # BMP: BM
    if MAGIC[0] == 66 {
        if MAGIC[1] == 77 { return 8; }
    }
    # ZIP: PK
    if MAGIC[0] == 80 {
        if MAGIC[1] == 75 { return 5; }
    }
    # shebang: #!
    if MAGIC[0] == 35 {
        if MAGIC[1] == 33 { return 10; }
    }
    # tar: 偏移 257 处是 "ustar"
    if load8(&MAGIC + 257) == 117 {
        if load8(&MAGIC + 258) == 115 {
            if load8(&MAGIC + 259) == 116 { return 3; }
        }
    }
    # 兜底：全是可打印 ASCII 就当纯文本
    let i: i64 = 0;
    while i < 64 {
        let c: i64 = MAGIC[i];
        if c == 0 { return 11; }
        if c < 32 {
            if c != 10 {
                if c != 9 {
                    if c != 13 { return 0; }
                }
            }
        }
        i = i + 1;
    }
    return 11;
}

fn magic_name() -> i64 {
    let t: i64 = magic_type();
    if t == 1 { return "ELF"; }
    if t == 2 { return "gzip"; }
    if t == 3 { return "tar"; }
    if t == 4 { return "PNG"; }
    if t == 5 { return "ZIP"; }
    if t == 6 { return "PDF"; }
    if t == 7 { return "JPEG"; }
    if t == 8 { return "BMP"; }
    if t == 9 { return "WebAssembly"; }
    if t == 10 { return "script"; }
    if t == 11 { return "text"; }
    return "unknown";
}

# ---- ELF64 元数据 ----
#
# ELF64 头布局（我们关心的部分）：
#   +0  魔数(4)   +4 EI_CLASS  +5 EI_DATA  +6 EI_VERSION
#   +16 e_type(2) +18 e_machine(2) +20 e_version(4)
#   +24 e_entry(8) +32 e_phoff(8) +40 e_shoff(8)
#   +58 e_phentsize(2) e_phnum(2) e_shentsize(2) e_shnum(2) e_shstrndx(2)

fn elf_is() -> i64 {
    if magic_type() != 1 { return 0; }
    return 1;
}

# 1 = 32 位，2 = 64 位
fn elf_class() -> i64 { return MAGIC[4]; }

# 1 = 小端，2 = 大端
fn elf_data() -> i64 { return MAGIC[5]; }

fn elf_version() -> i64 { return MAGIC[6]; }

fn elf_type() -> i64 { return MAGIC[16] + MAGIC[17] * 256; }

fn elf_machine() -> i64 { return MAGIC[18] + MAGIC[19] * 256; }

# 读 8 字节小端整数（i64 无符号语义，这里只用于偏移/入口这类正值）
fn rd64(off: i64) -> i64 {
    let v: i64 = 0;
    let i: i64 = 7;
    while i >= 0 {
        v = v * 256 + MAGIC[off + i];
        i = i - 1;
    }
    return v;
}

fn elf_entry() -> i64 { return rd64(24); }
fn elf_phoff() -> i64 { return rd64(32); }
fn elf_shoff() -> i64 { return rd64(40); }
fn elf_phnum() -> i64 { return MAGIC[56] + MAGIC[57] * 256; }
fn elf_shnum() -> i64 { return MAGIC[60] + MAGIC[61] * 256; }

fn elf_machine_name() -> i64 {
    let m: i64 = elf_machine();
    if m == 62 { return "x86-64"; }
    if m == 3 { return "i386"; }
    if m == 183 { return "AArch64"; }
    if m == 40 { return "ARM"; }
    if m == 243 { return "RISC-V"; }
    if m == 8 { return "MIPS"; }
    return "other";
}

fn elf_type_name() -> i64 {
    let t: i64 = elf_type();
    if t == 1 { return "REL"; }
    if t == 2 { return "EXEC"; }
    if t == 3 { return "DYN"; }
    if t == 4 { return "CORE"; }
    return "?";
}

# 是否是墨语言能直接运行的目标（x86-64 小端 EXEC/DYN）
fn elf_runnable_here() -> i64 {
    if elf_is() == 0 { return 0; }
    if elf_class() != 2 { return 0; }
    if elf_data() != 1 { return 0; }
    if elf_machine() != 62 { return 0; }
    return 1;
}
