# httpd —— 一个真的能用的 HTTP 服务器（用墨语言自己写的）
#
#   ./httpd 8080
#   curl http://127.0.0.1:8080/
#
# 支持：静态文本响应、/hello?name=xxx 的查询串、
#       /count 累计计数（演示有状态）、404 处理。
# 并发：每连接 fork 一个子进程。
import "io.mo";
import "str.mo";
import "net.mo";

var req: [8192] byte = 0;
var out: [8192] byte = 0;
var hits: i64 = 0;

# HTTP 响应头 + 空行 + 正文
fn respond(fd: i64, code: i64, ctype: i64, body: i64) -> i64 {
    let n: i64 = 0;
    if code == 200 {
        n = strcpy(&out, "HTTP/1.0 200 OK\r\n");
    } else {
        n = strcpy(&out, "HTTP/1.0 404 Not Found\r\n");
    }
    n = strcat(&out, "Content-Type: ");
    strcat(&out, ctype);
    strcat(&out, "\r\nContent-Length: ");
    let nb: [16] byte = 0;
    utoa(strlen(body), &nb, 10);
    strcat(&out, &nb);
    strcat(&out, "\r\nConnection: close\r\n\r\n");
    strcat(&out, body);
    tcp_send_str(fd, &out);
    return 0;
}

# 从 "GET /hello?name=bob HTTP/1.1" 里取路径（去掉查询串）
# 返回写在 path 里；同时把查询串起点存进 qp
fn parse_path(line: i64, path: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    # 跳过方法
    while load8(line + i) != 32 {
        if load8(line + i) == 0 { return 0; }
        i = i + 1;
    }
    i = i + 1;
    # 取到下一个空格或换行；遇 '?' 停下（查询串另算）
    while load8(line + i) != 0 {
        let c: i64 = load8(line + i);
        if c == 32 { break; }
        if c == 10 { break; }
        if c == 13 { break; }
        if c == 63 { break; }
        store8(path + j, c);
        j = j + 1;
        i = i + 1;
    }
    store8(path + j, 0);
    return j;
}

# 解析查询串 ?name=xxx，取 name 的值
fn query(line: i64, key: i64, dst: i64) -> i64 {
    let p: i64 = strchr(line, 63);
    if p < 0 { return 0; }
    let i: i64 = p + 1;
    let n: i64 = strlen(line);
    while i < n {
        # 找 key=
        let j: i64 = 0;
        while load8(key + j) != 0 {
            if load8(line + i + j) != load8(key + j) { break; }
            j = j + 1;
        }
        if load8(key + j) == 0 {
            if load8(line + i + j) == 61 {
                let s: i64 = i + j + 1;
                let k: i64 = 0;
                while load8(line + s) != 0 {
                    let c: i64 = load8(line + s);
                    if c == 38 { break; }
                    if c == 32 { break; }
                    store8(dst + k, c);
                    k = k + 1;
                    s = s + 1;
                }
                store8(dst + k, 0);
                return k;
            }
        }
        # 跳到下一个 &
        while i < n {
            if load8(line + i) == 38 { break; }
            i = i + 1;
        }
        i = i + 1;
    }
    return 0;
}

fn handle(fd: i64) -> i64 {
    let n: i64 = tcp_recv(fd, &req, 8191);
    if n <= 0 { return 0; }
    store8(&req + n, 0);

    let path: [256] byte = 0;
    parse_path(&req, &path);

    if streq(&path, "/") == 1 {
        let b: [512] byte = 0;
        strcpy(&b, "<h1>mo httpd</h1><p>served by a language that compiles itself</p>");
        respond(fd, 200, "text/html", &b);
        return 0;
    }
    if streq(&path, "/hello") == 1 {
        let nm: [128] byte = 0;
        if query(&req, "name", &nm) == 0 {
            strcpy(&nm, "world");
        }
        let b: [512] byte = 0;
        strcpy(&b, "Hello, ");
        strcat(&b, &nm);
        strcat(&b, "!\n");
        respond(fd, 200, "text/plain", &b);
        return 0;
    }
    if streq(&path, "/count") == 1 {
        let b: [128] byte = 0;
        utoa(hits, &b, 10);
        strcat(&b, "\n");
        respond(fd, 200, "text/plain", &b);
        return 0;
    }
    let b2: [256] byte = 0;
    strcpy(&b2, "not found: ");
    strcat(&b2, &path);
    strcat(&b2, "\n");
    respond(fd, 404, "text/plain", &b2);
    return 0;
}

fn main() -> i64 {
    let port: i64 = 8080;
    if argc() > 1 {
        port = atoi(argv(1));
    }
    let fd: i64 = tcp_listen(port, 16);
    if fd < 0 {
        print("httpd: cannot listen on ");
        print_i64(port);
        print_nl();
        return 1;
    }
    print("httpd listening on ");
    print_i64(port);
    print_nl();

    while 1 {
        let c: i64 = tcp_accept(fd);
        if c < 0 { continue; }
        hits = hits + 1;
        let pid: i64 = fork();
        if pid == 0 {
            handle(c);
            tcp_close(c);
            exit(0);
        }
        tcp_close(c);
    }
    return 0;
}
