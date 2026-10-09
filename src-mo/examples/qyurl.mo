# qyurl —— URL 抓取器/HTTP 探测器（墨语言实战工具 #5）
#
# 解析 http://host:port/path，建立 TCP 连接，发送 GET，打印响应头
# 与正文（或 -o 保存正文到文件）。支持 -s 状态码模式（探测用）。
# 实战压测点：字符串解析（host/port/path 拆分）、TCP 客户端、
# 状态机式响应解析（头/体分离、Content-Length 分块读取）。
import "io.mo";
import "fs.mo";
import "str.mo";
import "net.mo";

var url_buf: [2048] byte = 0;
var host: [256] byte = 0;
var path: [1024] byte = 0;
var req: [2048] byte = 0;
var resp: [65536] byte = 0;
var line: [512] byte = 0;
var outpath: [256] byte = 0;

var port: i64 = 80;
var flag_status: i64 = 0;    # -s
var flag_out: i64 = 0;       # -o path

# 解析 URL：http://host[:port]/path
fn parse_url(u: i64) -> i64 {
    strcpy(&host, "");
    strcpy(&path, "/");
    port = 80;
    # 跳过 http://
    let p: i64 = u;
    if strstr(p, "http://") == 0 {
        p = p + 7;
    }
    # host[:port][/path]
    let h: i64 = &host;
    while load8(p) != 0 && load8(p) != 47 && load8(p) != 58 {
        store8(h, load8(p));
        h = h + 1;
        p = p + 1;
    }
    store8(h, 0);
    if load8(p) == 58 {
        p = p + 1;
        let v: i64 = 0;
        while load8(p) >= 48 && load8(p) <= 57 {
            v = v * 10 + (load8(p) - 48);
            p = p + 1;
        }
        port = v;
    }
    if load8(p) == 47 {
        strcpy(&path, p);
    }
    return 0;
}

# 从响应 buf 提取状态码
fn status_code(buf: i64) -> i64 {
    # "HTTP/1.x NNN ..."
    let i: i64 = 0;
    while load8(buf + i) != 32 && i < 20 { i = i + 1; }
    if load8(buf + i) != 32 { return 0; }
    i = i + 1;
    let v: i64 = 0;
    while load8(buf + i) >= 48 && load8(buf + i) <= 57 {
        v = v * 10 + (load8(buf + i) - 48);
        i = i + 1;
    }
    return v;
}

# 找头结束位置（\r\n\r\n），返回正文偏移；找不到返回 -1
fn body_offset(buf: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i + 3 < n {
        if load8(buf + i) == 13 && load8(buf + i + 1) == 10
        && load8(buf + i + 2) == 13 && load8(buf + i + 3) == 10 {
            return i + 4;
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn main() -> i64 {
    # 参数解析
    let target: i64 = 0;
    let a: i64 = 1;
    while a < argc() {
        let arg: i64 = argv(a);
        if streq(arg, "-s") == 1 {
            flag_status = 1;
        } else if streq(arg, "-o") == 1 {
            flag_out = 1;
            a = a + 1;
            if a < argc() { strcpy(&outpath, argv(a)); }
        } else {
            target = arg;
        }
        a = a + 1;
    }
    if target == 0 {
        print("用法: qyurl [-s] [-o 文件] http://host[:port]/path\n");
        return 1;
    }
    parse_url(target);
    if flag_status == 0 {
        print("连接 ");
        print(&host);
        print(":");
        print_i64(port);
        print(&path);
        print("\n");
    }
    let fd: i64 = tcp_connect_host(&host, port);
    if fd < 0 {
        print("!! 连接失败\n");
        return 1;
    }
    strcpy(&req, "GET ");
    strcat(&req, &path);
    strcat(&req, " HTTP/1.0\r\nHost: ");
    strcat(&req, &host);
    strcat(&req, "\r\nUser-Agent: qyurl/1.0 (qiyuan mo)\r\nConnection: close\r\n\r\n");
    tcp_send_str(fd, &req);
    # 接收
    memset(&resp, 0, 65536);
    let total: i64 = 0;
    let r: i64 = 0;
    while total < 65000 {
        r = tcp_recv(fd, &resp + total, 65000 - total);
        if r <= 0 { break; }
        total = total + r;
    }
    tcp_close(fd);
    if total <= 0 {
        print("!! 无响应\n");
        return 1;
    }
    store8(&resp + total, 0);
    let code: i64 = status_code(&resp);
    let bo: i64 = body_offset(&resp, total);
    if flag_status == 1 {
        print_i64(code);
        print("\n");
        return 0;
    }
    print("状态: ");
    print_i64(code);
    print("\n头大小: ");
    if bo > 0 { print_i64(bo - 4); } else { print("未知"); }
    print(" 正文: ");
    if bo > 0 { print_i64(total - bo); } else { print("0"); }
    print("\n");
    if bo > 0 {
        if flag_out == 1 {
            let ofd: i64 = fopen(&outpath, 577, 420);
            if ofd < 0 {
                print("!! 写文件失败\n");
                return 1;
            }
            fwrite(ofd, &resp + bo, total - bo);
            fclose(ofd);
            print("已保存: ");
            print(&outpath);
            print("\n");
        } else {
            print("---- 正文 ----\n");
            syscall(1, 1, &resp + bo, total - bo, 0, 0, 0);
            print("\n");
        }
    }
    return 0;
}
