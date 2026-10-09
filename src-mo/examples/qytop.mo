# qytop —— 进程监视器（墨语言实战工具 #9）
#
# 用法:
#   qytop              每 2 秒刷新进程列表（按内存降序，前 15 行）
#   qytop <次数>       刷新 N 次后退出（用于非交互测试）
#   qytop -i <毫秒>    自定义刷新间隔
#
# 实战压测点：sleep_ns 时序、ANSI 转义清屏、循环体内全局缓冲复用
# （qyps 的记录表每次 scan 前必须 recn=0——重入陷阱的循环版）、
# Ctrl-C 退出（SIGINT 默认行为）。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";
import "pty.mo";
import "net.mo";

var names: [64000] byte = 0;
var types: [250] byte = 0;
var stfile: [256] byte = 0;
var sfile: [256] byte = 0;
var buf: [4096] byte = 0;
var buf2: [8192] byte = 0;

var recs: [131072] byte = 0;   # 512 条 × 256 字节
var recn: i64 = 0;
var mems: [512] i64 = 0;

var nbuf: [24] byte = 0;
var tmp: [24] byte = 0;

fn numfits(s: i64) -> i64 {
    if strlen(s) == 0 { return 0; }
    let i: i64 = 0;
    while i < strlen(s) {
        let c: i64 = load8(s + i);
        if c < 48 || c > 57 { return 0; }
        i = i + 1;
    }
    return 1;
}

fn pid_str(v: i64, dst: i64) -> i64 {
    let d: i64 = 0;
    let x: i64 = v;
    if x == 0 { store8(&tmp, 48); d = 1; }
    while x > 0 {
        store8(&tmp + d, 48 + (x % 10));
        d = d + 1;
        x = x / 10;
    }
    let i: i64 = 0;
    while i < d {
        store8(dst + i, load8(&tmp + d - 1 - i));
        i = i + 1;
    }
    store8(dst + d, 0);
    return 0;
}

fn store_i64(p: i64, v: i64) -> i64 {
    store8(p, v & 255);
    store8(p + 1, (v / 256) & 255);
    store8(p + 2, (v / 65536) & 255);
    store8(p + 3, (v / 16777216) & 255);
    store8(p + 4, (v / 4294967296) & 255);
    store8(p + 5, (v / 1099511627776) & 255);
    store8(p + 6, (v / 281474976710656) & 255);
    store8(p + 7, (v / 72057594037927936) & 255);
    return 0;
}

fn load_i64(p: i64) -> i64 {
    return load8(p) + load8(p + 1) * 256 + load8(p + 2) * 65536 + load8(p + 3) * 16777216
         + load8(p + 4) * 4294967296 + load8(p + 5) * 1099511627776
         + load8(p + 6) * 281474976710656 + load8(p + 7) * 72057594037927936;
}

fn parse_stat(pid: i64, rec: i64) -> i64 {
    pid_str(pid, &nbuf);
    strcpy(&stfile, "/proc/");
    strcat(&stfile, &nbuf);
    strcat(&stfile, "/stat");
    let n: i64 = read_file(&stfile, &buf, 4000);
    if n <= 0 { return 0 - 1; }
    store8(&buf + n, 0);
    let p: i64 = strchr(&buf, 40);
    if p < 0 { return 0 - 1; }
    let q: i64 = &buf + p + 1;
    while load8(q) != 0 && load8(q) != 41 { q = q + 1; }
    let nlen: i64 = q - (&buf + p + 1);
    if nlen > 200 { nlen = 200; }
    memcpy(rec + 17, &buf + p + 1, nlen);
    store8(rec + 17 + nlen, 0);
    let st: i64 = q + 2;
    store8(rec + 16, load8(st));
    let f: i64 = st + 1;
    let fc: i64 = load8(f);
    while fc == 32 || fc == 9 {
        f = f + 1;
        fc = load8(f);
    }
    store_i64(rec + 8, atoi(f));
    store_i64(rec + 0, pid);
    return 0;
}

fn parse_status(pid: i64, idx: i64) -> i64 {
    pid_str(pid, &nbuf);
    strcpy(&sfile, "/proc/");
    strcat(&sfile, &nbuf);
    strcat(&sfile, "/status");
    let n: i64 = read_file(&sfile, &buf2, 8000);
    if n <= 0 { mems[idx] = 0 - 1; return 0 - 1; }
    store8(&buf2 + n, 0);
    let p: i64 = strstr(&buf2, "VmRSS:");
    if p < 0 { mems[idx] = 0; return 0; }
    let f: i64 = &buf2 + p + 6;
    let fc: i64 = load8(f);
    while fc == 32 || fc == 9 {
        f = f + 1;
        fc = load8(f);
    }
    mems[idx] = atoi(f);
    return 0;
}

fn scan() -> i64 {
    let n: i64 = dir_list("/proc", &names, &types, 256, 249);
    if n < 0 { return 0 - 1; }
    recn = 0;
    let i: i64 = 0;
    while i < n {
        let nm: i64 = &names + i * 256;
        if numfits(nm) == 1 {
            if recn < 512 {
                let rec: i64 = &recs + recn * 256;
                if parse_stat(atoi(nm), rec) == 0 {
                    parse_status(atoi(nm), recn);
                    recn = recn + 1;
                }
            }
        }
        i = i + 1;
    }
    return recn;
}

fn sort_by_mem() -> i64 {
    let i: i64 = 0;
    while i < recn {
        let j: i64 = 0;
        while j + 1 < recn - i {
            let a: i64 = &recs + j * 256;
            let b: i64 = &recs + (j + 1) * 256;
            if mems[j] < mems[j + 1] {
                let t: i64 = 0;
                while t < 256 {
                    let tb: i64 = load8(a + t);
                    store8(a + t, load8(b + t));
                    store8(b + t, tb);
                    t = t + 1;
                }
                let tm: i64 = mems[j];
                mems[j] = mems[j + 1];
                mems[j + 1] = tm;
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

fn show_top(max_rows: i64) -> i64 {
    # ANSI: 清屏 + 光标回原点（mo 字符串不支持 \x 转义，直接写字节）
    let esc: [8] byte = 0;
    store8(&esc + 0, 27);
    store8(&esc + 1, 91);
    store8(&esc + 2, 50);
    store8(&esc + 3, 74);
    store8(&esc + 4, 27);
    store8(&esc + 5, 91);
    store8(&esc + 6, 72);
    store8(&esc + 7, 0);
    print(&esc);
    print("qytop  PID/PPID/状态/内存(降序前 ");
    print_i64(max_rows);
    print(")  Ctrl-C 退出\n");
    print("  PID  PPID S    MEM(kB)  名称\n");
    let rows: i64 = recn;
    if rows > max_rows { rows = max_rows; }
    let i: i64 = 0;
    while i < rows {
        let rec: i64 = &recs + i * 256;
        print_i64(load_i64(rec + 0));
        print(" ");
        print_i64(load_i64(rec + 8));
        print(" ");
        let sc: [2] byte = 0;
        store8(&sc, load8(rec + 16));
        store8(&sc + 1, 0);
        print(&sc);
        print(" ");
        print_i64(mems[i]);
        print(" ");
        print(rec + 17);
        print("\n");
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    let interval_ms: i64 = 2000;
    let rounds: i64 = 0 - 1;   # 无限
    if argc() >= 2 {
        let a: i64 = argv(1);
        if streq(a, "-i") == 1 {
            if argc() >= 3 { interval_ms = atoi(argv(2)); }
        } else {
            rounds = atoi(a);
        }
    }
    if rounds == 0 { rounds = 1; }
    let r: i64 = 0;
    while rounds < 0 || r < rounds {
        scan();
        sort_by_mem();
        show_top(15);
        if rounds < 0 || r + 1 < rounds {
            sleep_ns(interval_ms * 1000000);
        }
        r = r + 1;
    }
    return 0;
}
