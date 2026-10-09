# qycp —— 文件拷贝工具（墨语言实战工具 #14）
#
# 用法:
#   qycp <源> <目标>            拷贝文件
#   qycp -r <源目录> <目标目录>  递归拷贝目录
#   qycp -f <源> <目标>         目标存在时覆盖（默认拒绝）
#   qycp -p <源> <目标>         保留权限位
#
# 实战压测点：read/write 分块拷贝、目录递归（深度分槽路径）、
# 权限保留（stat_mode 取低 12 位 → chmod）、mkdir_p、
# 目标为已存在目录时自动拼文件名（cp 语义）。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var fbuf: [65536] byte = 0;
var dir_names: [64000] byte = 0;
var dir_types: [250] byte = 0;
var paths: [8192] byte = 0;      # 8 槽 × 1024
var dst_buf: [1024] byte = 0;
var parent: [1024] byte = 0;

var force: i64 = 0;
var keep_perm: i64 = 0;
var recursive: i64 = 0;

fn dirp(p: i64) -> i64 {
    let m: i64 = stat_mode(p);
    if m < 0 { return 0 - 1; }
    if (m & 61440) == 16384 { return 1; }
    return 0;
}

# 取路径最后一段（文件名）
fn basename_of(p: i64, dst: i64) -> i64 {
    let n: i64 = strlen(p);
    let i: i64 = n - 1;
    while i >= 0 {
        if load8(p + i) == 47 { i = i + 1; break; }
        i = i - 1;
    }
    if i < 0 { i = 0; }
    let j: i64 = 0;
    while load8(p + i) != 0 {
        store8(dst + j, load8(p + i));
        i = i + 1;
        j = j + 1;
    }
    store8(dst + j, 0);
    return 0;
}

fn parent_of(p: i64, dst: i64) -> i64 {
    let n: i64 = strlen(p);
    let i: i64 = n - 1;
    while i >= 0 {
        if load8(p + i) == 47 {
            if i == 0 { store8(dst, 47); store8(dst + 1, 0); return 0; }
            memcpy(dst, p, i);
            store8(dst + i, 0);
            return 0;
        }
        i = i - 1;
    }
    return 0 - 1;
}

fn mkdir_p(p: i64) -> i64 {
    if strlen(p) == 0 { return 0; }
    let r: i64 = mkdir(p, 493);
    if r == 0 { return 0; }
    let e: i64 = 0 - r;
    if e == 17 { return 0; }
    if e == 2 {
        if parent_of(p, &parent) == 0 {
            mkdir_p(&parent);
            r = mkdir(p, 493);
            if r == 0 { return 0; }
            if 0 - r == 17 { return 0; }
        }
        return 0 - 1;
    }
    return 0 - 1;
}

# 拷贝单个文件内容；返回 0 成功
fn copy_data(src: i64, dst: i64) -> i64 {
    let s: i64 = stat_size(src);
    if s < 0 { return 0 - 1; }
    let fd1: i64 = fopen(src, 0, 0);
    if fd1 < 0 { return 0 - 1; }
    let fd2: i64 = fopen(dst, 577, 438);   # O_WRONLY|O_CREAT|O_TRUNC 0666
    if fd2 < 0 { fclose(fd1); return 0 - 1; }
    let total: i64 = 0;
    while 1 == 1 {
        let n: i64 = fread(fd1, &fbuf, 65536);
        if n <= 0 { break; }
        if fwrite(fd2, &fbuf, n) != n {
            fclose(fd1); fclose(fd2);
            return 0 - 1;
        }
        total = total + n;
    }
    fclose(fd1);
    fclose(fd2);
    if total != s { return 0 - 1; }
    return 0;
}

fn copy_file(src: i64, dst: i64) -> i64 {
    # 目标是已存在目录 → 拼上源文件名
    let real: i64 = dst;
    if dirp(dst) == 1 {
        strcpy(&dst_buf, dst);
        strcat(&dst_buf, "/");
        let nm: [256] byte = 0;
        basename_of(src, &nm);
        strcat(&dst_buf, &nm);
        real = &dst_buf;
    }
    if force == 0 && stat_size(real) >= 0 {
        print("qycp: 目标已存在（-f 覆盖）: ");
        print(real);
        print("\n");
        return 0 - 1;
    }
    if copy_data(src, real) != 0 {
        print("qycp: 失败: ");
        print(real);
        print("\n");
        return 0 - 1;
    }
    if keep_perm == 1 {
        let m: i64 = stat_mode(src);
        if m >= 0 { chmod(real, m & 4095); }
    }
    return 0;
}

# 递归拷贝目录（路径按深度分槽）
fn copy_dir(depth: i64) -> i64 {
    if depth > 6 { return 0; }
    let here: i64 = &paths + depth * 1024;          # 源目录
    let here_dst: i64 = &paths + (depth + 4) * 1024; # 对应目标目录
    let n: i64 = dir_list(here, &dir_names, &dir_types, 256, 249);
    if n < 0 { return 0; }
    let child: i64 = &paths + (depth + 1) * 1024;
    let child_dst: i64 = &paths + (depth + 5) * 1024;
    let i: i64 = 0;
    while i < n {
        let nm: i64 = &dir_names + i * 256;
        if streq(nm, ".") != 1 && streq(nm, "..") != 1 {
            strcpy(child, here);
            strcat(child, "/");
            strcat(child, nm);
            strcpy(child_dst, here_dst);
            strcat(child_dst, "/");
            strcat(child_dst, nm);
            if load8(&dir_types + i) == 4 {
                mkdir_p(child_dst);
                copy_dir(depth + 1);
            } else {
                if force == 1 { unlink(child_dst); }
                copy_file(child, child_dst);
            }
        }
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    let i: i64 = 1;
    let pos: i64 = 0;
    let a_src: i64 = 0;
    let a_dst: i64 = 0;
    while i < argc() {
        let a: i64 = argv(i);
        if pos == 0 && load8(a) == 45 && load8(a + 1) != 0 {
            let j: i64 = 1;
            while load8(a + j) != 0 {
                if load8(a + j) == 114 { recursive = 1; }
                if load8(a + j) == 102 { force = 1; }
                if load8(a + j) == 112 { keep_perm = 1; }
                j = j + 1;
            }
        } else if pos == 0 {
            a_src = a;
            pos = 1;
        } else if pos == 1 {
            a_dst = a;
            pos = 2;
        }
        i = i + 1;
    }
    if pos < 2 {
        print("用法: qycp [-r] [-f] [-p] <源> <目标>\n");
        return 1;
    }
    if stat_size(a_src) < 0 {
        print("qycp: 源不存在: ");
        print(a_src);
        print("\n");
        return 1;
    }
    let src_is_dir: i64 = dirp(a_src);
    if 1 == src_is_dir && src_is_dir > 0 {
        if recursive == 0 {
            print("qycp: 源是目录（需要 -r）: ");
            print(a_src);
            print("\n");
            return 1;
        }
        # 目标：若已存在目录 → 拼源 basename；否则直接作为目标目录路径
        let tgt: i64 = a_dst;
        if dirp(a_dst) == 1 {
            strcpy(&dst_buf, a_dst);
            strcat(&dst_buf, "/");
            let nm: [256] byte = 0;
            basename_of(a_src, &nm);
            strcat(&dst_buf, &nm);
            tgt = &dst_buf;
        }
        mkdir_p(tgt);
        strcpy(&paths, a_src);              # depth 0 源
        strcpy(&paths + 4 * 1024, tgt);     # depth 0 目标
        copy_dir(0);
        print("copied dir ");
        print(a_src);
        print(" -> ");
        print(tgt);
        print("\n");
        return 0;
    }
    if copy_file(a_src, a_dst) == 0 {
        print("copied ");
        print(a_src);
        print(" -> ");
        print(a_dst);
        print("\n");
        return 0;
    }
    return 1;
}
