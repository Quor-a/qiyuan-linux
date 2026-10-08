# expect: 0
# 目录遍历、文件元数据、内核信息、魔数识别
import "io.mo";
import "str.mo";
import "fs.mo";
import "dir.mo";
import "binfmt.mo";

var nm: [256] byte = 0;
var u: [128] byte = 0;

fn main() -> i64 {
    # --- 目录：先造两个文件，再确认能列出来 ---
    let w: i64 = fopen("z1.txt", 577, 420);
    fwrite(w, "aaa\n", 4); fclose(w);
    let w2: i64 = fopen("z2.txt", 577, 420);
    fwrite(w2, "bbbbbb\n", 7); fclose(w2);

    if dir_open(".") != 0 { return 1; }
    let f1: i64 = 0;
    let f2: i64 = 0;
    while dir_next(&nm, 0) == 1 {
        if streq(&nm, "z1.txt") == 1 { f1 = 1; }
        if streq(&nm, "z2.txt") == 1 { f2 = 1; }
    }
    dir_close();
    if f1 == 0 { return 2; }
    if f2 == 0 { return 3; }

    # --- 元数据：大小与类型 ---
    if stat_size("z1.txt") != 4 { return 4; }
    if stat_size("z2.txt") != 7 { return 5; }
    if is_file("z1.txt") != 1 { return 6; }
    if is_dir(".") != 1 { return 7; }
    if is_file(".") != 0 { return 8; }
    if exists("nope.txt") != 0 { return 9; }
    if exists("z1.txt") != 1 { return 10; }

    # --- 目录操作：mkdir / rename / unlink ---
    if mkdir("zd", 493) != 0 { return 11; }
    if is_dir("zd") != 1 { return 12; }
    if rename("z2.txt", "zd/z3.txt") != 0 { return 13; }
    if exists("z2.txt") != 0 { return 14; }
    if unlink("zd/z3.txt") != 0 { return 15; }
    if exists("zd/z3.txt") != 0 { return 16; }

    # --- 内核信息 ---
    uname_sysname(&u);
    if streq(&u, "Linux") == 0 { return 17; }
    uname_machine(&u);
    if strlen(&u) == 0 { return 18; }
    if mem_total() <= 0 { return 19; }
    if uptime_secs() < 0 { return 20; }

    # --- 魔数：编出来的 ELF 必须能被认出来 ---
    if magic_load("z1.txt", 512) < 0 { return 21; }
    if magic_type() != 11 { return 22; }      # 纯文本

    print("sys ok\n");
    return 0;
}
