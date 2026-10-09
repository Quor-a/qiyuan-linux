import "str.mo";

# 文件与标准输入输出的薄封装
#   全部是对 syscall 的直接包装，不做缓冲
#   出错时返回 -1（与 C 的惯例一致）

# open(path, flags, mode) -> fd 或 -1
#   flags: 0=只读 O_CREAT|O_WRONLY|O_TRUNC=577
fn fopen(path: i64, flags: i64, mode: i64) -> i64 {
    return syscall(2, path, flags, mode, 0, 0, 0);
}

# read(fd, buf, n) -> 读到的字节数（0 表示 EOF，-1 表示出错）
fn fread(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(0, fd, buf, n, 0, 0, 0);
}

# write(fd, buf, n) -> 写入的字节数
fn fwrite(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(1, fd, buf, n, 0, 0, 0);
}

fn fclose(fd: i64) -> i64 {
    return syscall(3, fd, 0, 0, 0, 0, 0);
}

# 输出到 stdout
fn fputs(s: i64) -> i64 {
    return syscall(1, 1, s, strlen(s), 0, 0, 0);
}

# 一次性把文件读进 buf，返回字节数；失败返回 -1
# 会在末尾补一个 0，方便当字符串用。buf 至少要能装 n+1 字节。
fn read_file(path: i64, buf: i64, cap: i64) -> i64 {
    let fd: i64 = fopen(path, 0, 0);
    if fd < 0 {
        return -1;
    }
    let n: i64 = fread(fd, buf, cap - 1);
    fclose(fd);
    if n < 0 {
        return -1;
    }
    store8(buf + n, 0);
    return n;
}

# --- syscall 直通封装（qysh 实战回填） ---
fn chdir(p: i64) -> i64 {
    return syscall(80, p, 0, 0, 0, 0, 0);
}
fn getcwd(buf: i64, n: i64) -> i64 {
    return syscall(79, buf, n, 0, 0, 0, 0);
}
fn read(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(0, fd, buf, n, 0, 0, 0);
}
fn close(fd: i64) -> i64 {
    return syscall(3, fd, 0, 0, 0, 0, 0);
}
fn pipe_rw(pfd: i64) -> i64 {
    # pipe(2) 写两个 4 字节 int：低 4 字节=读端，高 4 字节=写端
    let r: i64 = syscall(22, pfd, 0, 0, 0, 0, 0);
    if r != 0 { return r; }
    let rd: i64 = load8(pfd) + load8(pfd + 1) * 256 + load8(pfd + 2) * 65536 + load8(pfd + 3) * 16777216;
    let wr: i64 = load8(pfd + 4) + load8(pfd + 5) * 256 + load8(pfd + 6) * 65536 + load8(pfd + 7) * 16777216;
    store64(pfd, rd + wr * 4294967296);
    return 0;
}
fn dup2(old: i64, new: i64) -> i64 {
    return syscall(33, old, new, 0, 0, 0, 0);
}
fn fork_now() -> i64 {
    return syscall(57, 0, 0, 0, 0, 0, 0);
}
fn wait_pid(p: i64) -> i64 {
    return syscall(61, p, 0, 0, 0, 0, 0);
}
fn execve(p: i64, argv: i64, envp: i64) -> i64 {
    return syscall(59, p, argv, envp, 0, 0, 0);
}
