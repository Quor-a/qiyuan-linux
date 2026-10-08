# pty —— 伪终端与进程控制（用墨语言自己写的）
#
# 直接用 open(/dev/ptmx) + ioctl(TIOCSPTLCK / TIOCGPTN) + open(/dev/pts/N)，
# 不依赖 libc 的 openpty/forkpty。
#
# 用途：给需要「像在终端里」运行的程序喂输入，
# 或者把子进程的输出按行取回来做处理。

import "fs.mo";
import "str.mo";
import "io.mo";

# ioctl 号（x86-64）
var TIOCSPTLCK: i64 = 1074025521;   # 0x40045431
var TIOCGPTN:   i64 = 2147767344;   # 0x80045430
var TIOCSWINSZ: i64 = 1074287719;   # 0x40085467

var pt_fd: i64 = 0;
var pt_num: i64 = 0;

# 打开主端，返回 0 表示成功
fn pty_master() -> i64 {
    pt_fd = syscall(2, "/dev/ptmx", 2, 0, 0, 0, 0);
    if pt_fd < 0 { return -1; }
    let unlock: i64 = 0;
    let r: i64 = syscall(16, pt_fd, TIOCSPTLCK, &unlock, 0, 0, 0);
    if r < 0 { return -2; }
    r = syscall(16, pt_fd, TIOCGPTN, &pt_num, 0, 0, 0);
    if r < 0 { return -3; }
    return 0;
}

# 从端路径写进 dst（形如 /dev/pts/3），返回 0 表示成功
fn pty_slave_path(dst: i64) -> i64 {
    strcpy(dst, "/dev/pts/");
    let t: [24] byte = 0;
    utoa(pt_num, &t, 10);
    strcat(dst, &t);
    return 0;
}

# 打开从端，返回 fd
fn pty_slave() -> i64 {
    let p: [64] byte = 0;
    pty_slave_path(&p);
    return syscall(2, &p, 2, 0, 0, 0, 0);
}

# 设置窗口大小（行列）
fn pty_winsize(rows: i64, cols: i64) -> i64 {
    let w: [8] byte = 0;
    store8(&w + 0, rows & 255);
    store8(&w + 1, (rows / 256) & 255);
    store8(&w + 2, cols & 255);
    store8(&w + 3, (cols / 256) & 255);
    return syscall(16, pt_fd, TIOCSWINSZ, &w, 0, 0, 0);
}

fn pty_write(s: i64) -> i64 {
    return syscall(1, pt_fd, s, strlen(s), 0, 0, 0);
}

fn pty_read(buf: i64, n: i64) -> i64 {
    return syscall(0, pt_fd, buf, n, 0, 0, 0);
}

fn pty_close() -> i64 {
    if pt_fd > 0 {
        syscall(3, pt_fd, 0, 0, 0, 0, 0);
        pt_fd = 0;
    }
    return 0;
}

# ---- 进程控制 ----

fn execve(path: i64, argv: i64, envp: i64) -> i64 {
    return syscall(59, path, argv, envp, 0, 0, 0);
}

# wait4：返回子进程退出码（低 8 位），失败返回 -1
fn waitpid(pid: i64) -> i64 {
    let st: i64 = 0;
    let r: i64 = syscall(61, pid, &st, 0, 0, 0, 0);
    if r < 0 { return -1; }
    return (st / 256) & 255;
}

fn kill(pid: i64, sig: i64) -> i64 {
    return syscall(62, pid, sig, 0, 0, 0, 0);
}

fn getpid() -> i64 {
    return syscall(39, 0, 0, 0, 0, 0, 0);
}
