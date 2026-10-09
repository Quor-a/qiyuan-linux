# qychmod —— 文件权限工具（墨语言实战工具 #13）
#
# 用法:
#   qychmod 755 <路径>        八进制权限（如 644/755/600）
#   qychmod -R 755 <目录>     递归
#   qychmod <路径>            查询当前权限（st_mode 八进制显示）
#
# 实战压测点：chmod 系统调用（fchmodat 简化为 chmod(90)）、八进制字符串
# 解析（无 atoi 的 8 进制版）、st_mode 提取与格式化、递归 + 深度分槽。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var fbuf: [65536] byte = 0;
var dir_names: [64000] byte = 0;
var dir_types: [250] byte = 0;
var paths: [7168] byte = 0;      # 7 槽 × 1024
var oct_buf: [8] byte = 0;
var nbuf: [24] byte = 0;

# 八进制字符串 → 数值（非法字符返回 -1）
fn octal(s: i64) -> i64 {
    let v: i64 = 0;
    let n: i64 = strlen(s);
    if n == 0 || n > 4 { return 0 - 1; }
    let i: i64 = 0;
    while i < n {
        let c: i64 = load8(s + i);
        if c < 48 || c > 55 { return 0 - 1; }   # 0-7
        v = v * 8 + (c - 48);
        i = i + 1;
    }
    return v;
}

# 数值 → 3 位八进制串
fn to_oct3(v: i64, dst: i64) -> i64 {
    store8(dst + 0, 48 + ((v / 64) & 7));
    store8(dst + 1, 48 + ((v / 8) & 7));
    store8(dst + 2, 48 + (v & 7));
    store8(dst + 3, 0);
    return 0;
}

fn sys_chmod(p: i64, mode: i64) -> i64 {
    return syscall(90, p, mode, 0, 0, 0, 0);
}

# 打印路径的权限 + 类型
fn show_mode(p: i64) -> i64 {
    let m: i64 = stat_mode(p);
    if m < 0 {
        print("qychmod: 打不开: ");
        print(p);
        print("\n");
        return 0 - 1;
    }
    let t: i64 = m & 61440;   # S_IFMT
    if t == 16384 { print("d"); }
    else if t == 32768 { print("-"); }
    else if t == 40960 { print("l"); }
    else { print("?"); }
    let perm: i64 = (m >> 6) & 7;
    to_oct3((m & 511), &oct_buf);
    print(&oct_buf);
    print(" ");
    print(p);
    print("\n");
    return 0;
}

fn chmod_one(p: i64, mode: i64) -> i64 {
    let r: i64 = sys_chmod(p, mode);
    if r != 0 {
        print("qychmod: 失败 (");
        print(p);
        print(") errno=");
        print_i64(0 - r);
        print("\n");
        return 0 - 1;
    }
    return 0;
}

# 递归 chmod（路径按深度分槽）
fn chmod_dir(depth: i64, mode: i64) -> i64 {
    if depth > 5 { return 0; }
    let here: i64 = &paths + depth * 1024;
    let n: i64 = dir_list(here, &dir_names, &dir_types, 256, 249);
    if n < 0 { return 0; }
    let child: i64 = &paths + (depth + 1) * 1024;
    let i: i64 = 0;
    while i < n {
        let nm: i64 = &dir_names + i * 256;
        if streq(nm, ".") != 1 && streq(nm, "..") != 1 {
            strcpy(child, here);
            strcat(child, "/");
            strcat(child, nm);
            chmod_one(child, mode);
            if load8(&dir_types + i) == 4 {
                chmod_dir(depth + 1, mode);
            }
        }
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    let recursive: i64 = 0;
    let idx: i64 = 1;
    if argc() < 2 {
        print("用法: qychmod [-R] <八进制权限> <路径> | qychmod <路径>\n");
        return 1;
    }
    let a1: i64 = argv(1);
    if streq(a1, "-R") == 1 {
        recursive = 1;
        idx = 2;
    }
    if argc() < idx + 1 {
        print("用法: qychmod [-R] <八进制权限> <路径> | qychmod <路径>\n");
        return 1;
    }
    let first: i64 = argv(idx);
    # 只有 1 个参数（或 -R 后 1 个）→ 查询模式
    if argc() == idx + 1 {
        return show_mode(first);
    }
    let mode: i64 = octal(first);
    if mode < 0 {
        print("qychmod: 无效权限: ");
        print(first);
        print("\n");
        return 1;
    }
    let target: i64 = argv(idx + 1);
    if stat_mode(target) < 0 {
        print("qychmod: 打不开: ");
        print(target);
        print("\n");
        return 1;
    }
    if recursive == 1 {
        let t: i64 = stat_mode(target) & 61440;
        if t == 16384 {
            strcpy(&paths, target);
            chmod_one(target, mode);
            chmod_dir(0, mode);
            return 0;
        }
    }
    if chmod_one(target, mode) == 0 {
        show_mode(target);
        return 0;
    }
    return 1;
}
