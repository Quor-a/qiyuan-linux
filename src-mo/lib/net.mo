# net —— 极简 TCP 网络库（用墨语言自己写的）
#
# 直接用 Linux syscall，不依赖 libc。
# 这是墨语言能做网络的前提：编译器直接产出 ELF64，
# 而 socket / bind / listen / accept / send / recv 全是系统调用，
# 不需要任何链接库。
#
# 只做 TCPv4 的服务端与客户端，够写一个真正的 HTTP 服务。

import "str.mo";   # strlen

var AF_INET: i64 = 2;
var SOCK_STREAM: i64 = 1;
var INADDR_ANY: i64 = 0;
var ts: [2] i64 = 0;   # sleep_ns 用的 timespec
var SOL_SOCKET: i64 = 1;
var SO_REUSEADDR: i64 = 2;

# 主机序 -> 网络序（16 位）
fn htons(p: i64) -> i64 {
    return ((p & 255) * 256) + ((p / 256) & 255);
}

# 填 sockaddr_in：family(2) + port(2, 网络序) + addr(4) + 填充(8)
fn sock_addr(buf: i64, addr: i64, port: i64) -> i64 {
    let np: i64 = htons(port);
    store8(buf + 0, AF_INET & 255);
    store8(buf + 1, 0);
    store8(buf + 2, (np / 256) & 255);
    store8(buf + 3, np & 255);
    store8(buf + 4, addr & 255);
    store8(buf + 5, (addr / 256) & 255);
    store8(buf + 6, (addr / 65536) & 255);
    store8(buf + 7, (addr / 16777216) & 255);
    let i: i64 = 8;
    while i < 16 {
        store8(buf + i, 0);
        i = i + 1;
    }
    return 16;
}

# socket(AF_INET, SOCK_STREAM, 0)
fn tcp_socket() -> i64 {
    return syscall(41, AF_INET, SOCK_STREAM, 0, 0, 0, 0);
}

# 允许端口复用，避免重启服务时 "address already in use"
fn sock_reuse(fd: i64) -> i64 {
    let opt: [4] i64 = 0;
    store8(&opt, 1);
    return syscall(54, fd, SOL_SOCKET, SO_REUSEADDR, &opt, 4, 0);
}

# 绑定并监听，返回监听 fd；失败返回负数
fn tcp_listen(port: i64, backlog: i64) -> i64 {
    let fd: i64 = tcp_socket();
    if fd < 0 { return fd; }
    sock_reuse(fd);
    let sa: [16] byte = 0;
    sock_addr(&sa, INADDR_ANY, port);
    let r: i64 = syscall(49, fd, &sa, 16, 0, 0, 0);
    if r < 0 { return 0 - 2; }
    r = syscall(50, fd, backlog, 0, 0, 0, 0);
    if r < 0 { return 0 - 3; }
    return fd;
}

# 接受一个连接，返回新的 fd（失败返回负数）。不关心对端地址
fn tcp_accept(fd: i64) -> i64 {
    return syscall(43, fd, 0, 0, 0, 0, 0);
}

# 连到 ip:port。ip 用 4 字节整数（如 127.0.0.1 写成 0x0100007f）
fn tcp_connect(ip: i64, port: i64) -> i64 {
    let fd: i64 = tcp_socket();
    if fd < 0 { return fd; }
    let sa: [16] byte = 0;
    sock_addr(&sa, ip, port);
    let r: i64 = syscall(42, fd, &sa, 16, 0, 0, 0);
    if r < 0 {
        syscall(3, fd, 0, 0, 0, 0, 0);
        return 0 - 1;
    }
    return fd;
}

# 收数据，返回字节数；0 表示对端关闭，负数表示出错
fn tcp_recv(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(45, fd, buf, n, 0, 0, 0);
}

# 发数据，返回发出的字节数
fn tcp_send(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(44, fd, buf, n, 0, 0, 0);
}

# 发送以 0 结尾的字符串
fn tcp_send_str(fd: i64, s: i64) -> i64 {
    # 不要写成 tcp_send(fd, s, strlen(s))：
    # 实参里嵌套函数调用会让外层函数名缓冲被内层覆盖，报 undefined symbol。
    # 先算出来再传，顺便避开这个坑。
    let n: i64 = strlen(s);
    return tcp_send(fd, s, n);
}

fn tcp_close(fd: i64) -> i64 {
    return syscall(3, fd, 0, 0, 0, 0, 0);
}

# fork：返回 0 表示子进程
fn fork() -> i64 {
    return syscall(57, 0, 0, 0, 0, 0, 0);
}

# 睡眠 nsec 纳秒。父子进程同步要用：
# 父进程必须等子进程 listen 完再 connect，否则会连不上。
fn sleep_ns(nsec: i64) -> i64 {
    store64(&ts, 0);
    store64(&ts + 8, nsec);
    return syscall(35, &ts, 0, 0, 0, 0, 0);
}

fn exit(code: i64) -> i64 {
    return syscall(60, code, 0, 0, 0, 0, 0);
}
