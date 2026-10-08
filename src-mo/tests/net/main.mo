# expect: 0
# 网络端到端：在同一个进程里 fork 出服务端与客户端，真实走 TCP 回环。
# 之所以不启后台进程：那样测例没法自包含。fork 让服务端与客户端都在测例内。
import "io.mo";
import "str.mo";
import "net.mo";

var PORT: i64 = 18471;
var cbuf: [512] byte = 0;

fn client() -> i64 {
    sleep_ns(300000000);          # 等服务端 listen
    let fd: i64 = tcp_connect(16777343, PORT);   # 127.0.0.1
    if fd < 0 { return 1; }
    let n: i64 = tcp_send_str(fd, "GET /ping HTTP/1.0\r\n\r\n");
    if n < 10 { return 2; }
    let m: i64 = tcp_recv(fd, &cbuf, 511);
    if m <= 0 { return 3; }
    store8(&cbuf + m, 0);
    tcp_close(fd);
    # 必须收到一个像样的 HTTP 响应
    if strstr(&cbuf, "HTTP/1.0 200 OK") < 0 { return 4; }
    if strstr(&cbuf, "pong") < 0 { return 5; }
    return 0;
}

fn server() -> i64 {
    let fd: i64 = tcp_listen(PORT, 4);
    if fd < 0 { return 10; }
    let c: i64 = tcp_accept(fd);
    if c < 0 { return 11; }
    let m: i64 = tcp_recv(c, &cbuf, 511);     # 复用缓冲（子进程，不冲突）
    if m <= 0 { return 12; }
    store8(&cbuf + m, 0);
    if strstr(&cbuf, "GET /ping") < 0 { return 13; }
    tcp_send_str(c, "HTTP/1.0 200 OK\r\nContent-Length: 4\r\n\r\npong");
    tcp_close(c);
    tcp_close(fd);
    return 0;
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        let r: i64 = server();
        exit(r);
    }
    let r: i64 = client();
    if r != 0 {
        print("net test failed: ");
        print_i64(r);
        print_nl();
        return r;
    }
    print("net ok: TCP 回环 + HTTP 响应往返\n");
    return 0;
}
