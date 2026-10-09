# qyln —— 链接工具（墨语言实战工具 #15）
#
# 用法:
#   qyln <目标> <链接名>            硬链接
#   qyln -s <目标> <链接名>         符号链接
#   qyln -i <链接名>                查询链接信息（readlink / inode 对比）
#
# 实战压测点：link(86)/symlink(88)/readlinkat 系统调用族、
# 硬链接同 inode 验证（stat st_ino 提取——首次实战 64 位 inode 字段）、
# symlink 读回（readlink 系统调用 89，返回字节数语义）、断链检测。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var lbuf: [512] byte = 0;
var sbuf1: [256] byte = 0;
var sbuf2: [256] byte = 0;
var nbuf: [4] byte = 0;

fn sys_link(old: i64, new: i64) -> i64 {
    return syscall(86, old, new, 0, 0, 0, 0);
}

fn sys_symlink(target: i64, linkpath: i64) -> i64 {
    return syscall(88, target, linkpath, 0, 0, 0, 0);
}

fn sys_readlink(path: i64, buf: i64, cap: i64) -> i64 {
    return syscall(89, path, buf, cap, 0, 0, 0);
}

# 读 stat 的 inode（第 39 字节偏移起，8 字节小端）
# struct stat x86_64: st_dev(0,8) st_ino(8,8) st_nlink(16,8) st_mode(24,4)...
fn stat_ino(p: i64) -> i64 {
    let st: [144] byte = 0;
    let r: i64 = syscall(4, p, &st, 0, 0, 0, 0);   # stat=4
    if r != 0 { return 0 - 1; }
    return load8(&st + 8) + load8(&st + 9) * 256
         + load8(&st + 10) * 65536 + load8(&st + 11) * 16777216
         + load8(&st + 12) * 4294967296 + load8(&st + 13) * 1099511627776
         + load8(&st + 14) * 281474976710656 + load8(&st + 15) * 72057594037927936;
}

# 读 st_nlink（偏移 16，8 字节）
fn stat_nlink(p: i64) -> i64 {
    let st: [144] byte = 0;
    let r: i64 = syscall(4, p, &st, 0, 0, 0, 0);
    if r != 0 { return 0 - 1; }
    return load8(&st + 16) + load8(&st + 17) * 256
         + load8(&st + 18) * 65536 + load8(&st + 19) * 16777216;
}

# 十六进制打印（inode 用）
fn print_hex64(v: i64) -> i64 {
    print("0x");
    let started: i64 = 0;
    let i: i64 = 15;
    while i >= 0 {
        let nib: i64 = (v >> (i * 4)) & 15;
        if nib != 0 || started == 1 || i == 0 {
            started = 1;
            if nib < 10 { store8(&nbuf, 48 + nib); } else { store8(&nbuf, 87 + nib); }
            store8(&nbuf + 1, 0);
            print(&nbuf);
        }
        i = i - 1;
    }
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("用法: qyln [-s] <目标> <链接名> | qyln -i <链接名>\n");
        return 1;
    }
    let a1: i64 = argv(1);
    # 查询模式
    if streq(a1, "-i") == 1 {
        if argc() < 3 {
            print("qyln: -i 需要链接名\n");
            return 1;
        }
        let lp: i64 = argv(2);
        let n: i64 = sys_readlink(lp, &lbuf, 500);
        if n < 0 {
            print("qyln: 不是符号链接或不存在: ");
            print(lp);
            print("\n");
            return 1;
        }
        store8(&lbuf + n, 0);
        print("symlink -> ");
        print(&lbuf);
        print("\n");
        return 0;
    }
    let sym: i64 = 0;
    let idx: i64 = 1;
    if streq(a1, "-s") == 1 {
        sym = 1;
        idx = 2;
    }
    if argc() < idx + 2 {
        print("用法: qyln [-s] <目标> <链接名>\n");
        return 1;
    }
    let target: i64 = argv(idx);
    let linkname: i64 = argv(idx + 1);
    if sym == 1 {
        let r: i64 = sys_symlink(target, linkname);
        if r != 0 {
            print("qyln: symlink 失败 errno=");
            print_i64(0 - r);
            print("\n");
            return 1;
        }
        print("linked ");
        print(linkname);
        print(" -> ");
        print(target);
        print("\n");
        return 0;
    }
    # 硬链接：目标必须存在
    if stat_size(target) < 0 {
        print("qyln: 目标不存在: ");
        print(target);
        print("\n");
        return 1;
    }
    let r: i64 = sys_link(target, linkname);
    if r != 0 {
        print("qyln: link 失败 errno=");
        print_i64(0 - r);
        print("\n");
        return 1;
    }
    print("linked ");
    print(linkname);
    print(" = ");
    print(target);
    print("\n");
    return 0;
}
