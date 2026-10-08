import "str.mo";
# dir —— 目录遍历与文件元数据（用墨语言自己写的）
#
# 直接用 getdents64(217) / stat(4) / uname(63) / sysinfo(99)，
# 不依赖 libc 的 opendir/readdir/stat —— 因为墨语言不链接任何库。
#
# getdents64 的 dirent64 布局（x86-64）：
#     +0   d_ino   (8)
#     +8   d_off   (8)
#     +16  d_reclen(2)
#     +18  d_type  (1)
#     +19  d_name  (变长，以 0 结尾)

var DT_UNKNOWN: i64 = 0;
var DT_REG: i64 = 8;
var DT_DIR: i64 = 4;

var d_fd: i64 = 0;
var d_buf: [65536] byte = 0;
var d_len: i64 = 0;
var d_pos: i64 = 0;

# 打开目录，返回 0 表示成功
fn dir_open(path: i64) -> i64 {
    d_fd = syscall(2, path, 65536, 0, 0, 0, 0);
    if d_fd < 0 { return -1; }
    d_len = 0;
    d_pos = 0;
    return 0;
}

# 读下一个条目：返回 1 表示取到，0 表示结束。名字写进 name
fn dir_next(name: i64, ty: i64) -> i64 {
    while 1 {
        if d_pos >= d_len {
            d_len = syscall(217, d_fd, &d_buf, 65536, 0, 0, 0);
            d_pos = 0;
            if d_len <= 0 { return 0; }
        }
        let base: i64 = &d_buf + d_pos;
        let reclen: i64 = load8(base + 16) + load8(base + 17) * 256;
        if reclen == 0 { return 0; }
        let t: i64 = load8(base + 18);
        # 拷名字
        let i: i64 = 0;
        while load8(base + 19 + i) != 0 {
            store8(name + i, load8(base + 19 + i));
            i = i + 1;
        }
        store8(name + i, 0);
        d_pos = d_pos + reclen;
        # 【启元修复】ty 参数此前收了但从未写入（上游 bug）——写 d_type
        if ty != 0 {
            store8(ty, t);
        }
        # 跳过 . 和 ..
        if load8(name) == 46 {
            if load8(name + 1) == 0 { continue; }
            if load8(name + 1) == 46 {
                if load8(name + 2) == 0 { continue; }
            }
        }
        return 1;
    }
    return 0;
}

fn dir_close() -> i64 {
    if d_fd > 0 {
        syscall(3, d_fd, 0, 0, 0, 0, 0);
        d_fd = 0;
    }
    return 0;
}

# 批量列目录：names 是 stride*count 的名字缓冲，types 是类型字节数组
# 返回条目数，出错返回 -1。类型：4=目录 8=普通文件（getdents64 d_type）
fn dir_list(path: i64, names: i64, types: i64, stride: i64, max: i64) -> i64 {
    if dir_open(path) < 0 { return -1; }
    let nb: [256] byte = 0;
    let t: [1] byte = 0;
    let n: i64 = 0;
    while dir_next(&nb, &t) == 1 {
        if n >= max { break; }
        let i: i64 = 0;
        while nb[i] != 0 {
            store8(names + n * stride + i, nb[i]);
            i = i + 1;
            if i >= stride - 1 { break; }
        }
        store8(names + n * stride + i, 0);
        # 【语言缺失#1】ptr 下标赋值 p[i]=v 不支持（读取支持），
        # 用 store8(names+n*stride+i, v) 代替；待改编译器补齐
        store8(types + n, t[0]);
        n = n + 1;
    }
    dir_close();
    return n;
}

# ---- stat(4) ----
# x86-64 struct stat 中我们关心的偏移：
#     +0  st_dev   +8  st_ino   +24 st_mode  +48 st_size
var st_buf: [144] byte = 0;

fn stat_size(path: i64) -> i64 {
    let r: i64 = syscall(4, path, &st_buf, 0, 0, 0, 0);
    if r < 0 { return -1; }
    let v: i64 = load8(&st_buf + 48) + load8(&st_buf + 49) * 256
               + load8(&st_buf + 50) * 65536 + load8(&st_buf + 51) * 16777216;
    return v;
}

fn stat_mode(path: i64) -> i64 {
    let r: i64 = syscall(4, path, &st_buf, 0, 0, 0, 0);
    if r < 0 { return -1; }
    return load8(&st_buf + 24) + load8(&st_buf + 25) * 256;
}

# 是否为普通文件 / 目录
fn is_dir(path: i64) -> i64 {
    let m: i64 = stat_mode(path);
    if m < 0 { return 0; }
    if ((m / 4096) & 15) == 4 { return 1; }   # 注意：必须加括号，== 比 & 结合更紧
    return 0;
}

fn is_file(path: i64) -> i64 {
    let m: i64 = stat_mode(path);
    if m < 0 { return 0; }
    if ((m / 4096) & 15) == 8 { return 1; }
    return 0;
}

fn exists(path: i64) -> i64 {
    if stat_mode(path) < 0 { return 0; }
    return 1;
}

# 改权限：chmod(path, mode) —— 对应「权限」需求
fn chmod(path: i64, mode: i64) -> i64 {
    return syscall(90, path, mode, 0, 0, 0, 0);
}

fn mkdir(path: i64, mode: i64) -> i64 {
    return syscall(83, path, mode, 0, 0, 0, 0);
}

fn unlink(path: i64) -> i64 {
    return syscall(87, path, 0, 0, 0, 0, 0);
}

fn rename(old: i64, new: i64) -> i64 {
    return syscall(82, old, new, 0, 0, 0, 0);
}

# ---- uname(63) / sysinfo(99)：读内核信息 ----
var u_buf: [390] byte = 0;

fn uname_field(which: i64, dst: i64) -> i64 {
    let r: i64 = syscall(63, &u_buf, 0, 0, 0, 0, 0);
    if r < 0 { return -1; }
    # utsname 每个字段 65 字节
    let p: i64 = &u_buf + which * 65;
    strcpy(dst, p);
    return 0;
}

fn uname_sysname(dst: i64) -> i64 { return uname_field(0, dst); }
fn uname_nodename(dst: i64) -> i64 { return uname_field(1, dst); }
fn uname_release(dst: i64) -> i64 { return uname_field(2, dst); }
fn uname_version(dst: i64) -> i64 { return uname_field(3, dst); }
fn uname_machine(dst: i64) -> i64 { return uname_field(4, dst); }

# 返回总内存（字节），来自 sysinfo
fn mem_total() -> i64 {
    let s: [112] byte = 0;
    let r: i64 = syscall(99, &s, 0, 0, 0, 0, 0);
    if r < 0 { return -1; }
    let v: i64 = 0;
    let i: i64 = 7;
    while i >= 0 {
        v = v * 256 + load8(&s + 32 + i);
        i = i - 1;
    }
    return v;
}

fn uptime_secs() -> i64 {
    let s: [112] byte = 0;
    let r: i64 = syscall(99, &s, 0, 0, 0, 0, 0);
    if r < 0 { return -1; }
    let v: i64 = 0;
    let i: i64 = 7;
    while i >= 0 {
        v = v * 256 + load8(&s + i);
        i = i - 1;
    }
    return v;
}
