# qyps —— 进程查看器（墨语言实战工具 #7）
#
# 用法:
#   qyps              列出全部进程（PID / 状态 / 父PID / 名称 / 内存）
#   qyps <关键词>     只显示名称含关键词的进程
#   qyps -s mem       按内存降序
#   qyps -s name      按名称排序
#
# 实战压测点：procfs 伪文件遍历、/proc/<pid>/stat 与 status 多文件解析、
# 定长记录表收集 + 冒泡排序、按数值/字符串两种键排序。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var names: [64000] byte = 0;
var types: [250] byte = 0;
var sfile: [256] byte = 0;
var stfile: [256] byte = 0;
var buf: [4096] byte = 0;
var buf2: [8192] byte = 0;

# 记录表：最多 512 进程，每条 256 字节（pid/ppid/state/name 打包）
var recs: [131072] byte = 0;   # 512 * 256（语法不支持表达式维度）
var recn: i64 = 0;

var filter: [128] byte = 0;
var sortkey: i64 = 0;   # 0=pid 1=mem 2=name
var mems: [512] i64 = 0;

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
    return load8(p) + load8(p+1)*256 + load8(p+2)*65536 + load8(p+3)*16777216
         + load8(p+4)*4294967296 + load8(p+5)*1099511627776
         + load8(p+6)*281474976710656 + load8(p+7)*72057594037927936;
}

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

# 从 /proc/<pid>/stat 提取：comm(括号内)、state(字段3)、ppid(字段4)
# 结果写入 rec 区：+0 pid(i64) +8 ppid(i64) +16 state byte +17 name
fn parse_stat(pid: i64, rec: i64) -> i64 {
    strcpy(&stfile, "/proc/");
    strcat(&stfile, "/");
    store8(&stfile + 5, 0);
    # 直接拼数字（不用 itoa，避免又依赖）
    let nbuf: [24] byte = 0;
    let v: i64 = pid;
    let d: i64 = 0;
    let tmp: [24] byte = 0;
    if v == 0 { store8(&tmp, 48); d = 1; }
    while v > 0 {
        store8(&tmp + d, 48 + (v % 10));
        d = d + 1;
        v = v / 10;
    }
    # 反转进 nbuf
    let i: i64 = 0;
    while i < d {
        store8(&nbuf + i, load8(&tmp + d - 1 - i));
        i = i + 1;
    }
    store8(&nbuf + d, 0);
    strcpy(&stfile, "/proc/");
    strcat(&stfile, &nbuf);
    strcat(&stfile, "/stat");

    let n: i64 = read_file(&stfile, &buf, 4000);
    if n <= 0 { return 0 - 1; }
    store8(&buf + n, 0);
    # comm 在第一个 '(' 与最后一个 ')' 之间
    let p: i64 = strchr(&buf, 40);
    if p < 0 { return 0 - 1; }
    let q: i64 = &buf + p + 1;
    # 找匹配的 ')'（取最后一个 ')' 更稳，但这里用第一个紧邻的 ')'）
    while load8(q) != 0 && load8(q) != 41 { q = q + 1; }
    let nlen: i64 = q - (&buf + p + 1);
    if nlen > 200 { nlen = 200; }
    memcpy(rec + 17, &buf + p + 1, nlen);
    store8(rec + 17 + nlen, 0);
    # state 在 ") " 之后
    let st: i64 = q + 2;
    store8(rec + 16, load8(st));
    # ppid = state 之后的第一个字段（跳过空格后第一个数字）
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

# 从 /proc/<pid>/status 取 VmRSS（kB）→ mems 数组
fn parse_status(pid: i64, idx: i64) -> i64 {
    store8(&sfile, 0);
    strcpy(&sfile, "/proc/");
    let nbuf: [24] byte = 0;
    let v: i64 = pid;
    let d: i64 = 0;
    let tmp: [24] byte = 0;
    if v == 0 { store8(&tmp, 48); d = 1; }
    while v > 0 {
        store8(&tmp + d, 48 + (v % 10));
        d = d + 1;
        v = v / 10;
    }
    let i: i64 = 0;
    while i < d {
        store8(&nbuf + i, load8(&tmp + d - 1 - i));
        i = i + 1;
    }
    store8(&nbuf + d, 0);
    strcpy(&sfile, "/proc/");
    strcat(&sfile, &nbuf);
    strcat(&sfile, "/status");
    let n: i64 = read_file(&sfile, &buf2, 8000);
    if n <= 0 { mems[idx] = 0 - 1; return 0 - 1; }
    store8(&buf2 + n, 0);
    # 找 "VmRSS:"
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
                let pid: i64 = atoi(nm);
                let rec: i64 = &recs + recn * 256;
                if parse_stat(pid, rec) == 0 {
                    parse_status(pid, recn);
                    recn = recn + 1;
                }
            }
        }
        i = i + 1;
    }
    return recn;
}

# 冒泡排序（按 sortkey），同步交换 mems
fn sort_recs() -> i64 {
    let i: i64 = 0;
    while i < recn {
        let j: i64 = 0;
        while j + 1 < recn - i {
            let a: i64 = &recs + j * 256;
            let b: i64 = &recs + (j + 1) * 256;
            let swap: i64 = 0;
            if sortkey == 1 {
                if mems[j] < mems[j + 1] { swap = 1; }
            } else {
                if load_i64(a + 0) > load_i64(b + 0) { swap = 1; }
            }
            if swap == 1 {
                let t: i64 = 0;
                while t < 256 {
                    let tmpb: i64 = load8(a + t);
                    store8(a + t, load8(b + t));
                    store8(b + t, tmpb);
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

fn main() -> i64 {
    let a1: i64 = 0;
    if argc() >= 2 {
        let m: i64 = argv(1);
        if streq(m, "-s") == 1 {
            if argc() >= 3 {
                let k: i64 = argv(2);
                if streq(k, "mem") == 1 { sortkey = 1; }
                else if streq(k, "name") == 1 { sortkey = 2; }
            }
        } else {
            strcpy(&filter, m);
        }
    }
    let c: i64 = scan();
    if c < 0 { print("qyps: 无法读取 /proc\n"); return 1; }
    sort_recs();
    print("  PID  PPID S    MEM(kB)  名称\n");
    let i: i64 = 0;
    while i < c {
        let rec: i64 = &recs + i * 256;
        let nm: i64 = rec + 17;
        let show: i64 = 1;
        if strlen(&filter) > 0 {
            if strstr(nm, &filter) < 0 { show = 0; }
        }
        if show == 1 {
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
            print(nm);
            print("\n");
        }
        i = i + 1;
    }
    return 0;
}
