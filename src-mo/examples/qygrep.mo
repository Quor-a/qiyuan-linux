# qygrep —— 文本搜索工具（墨语言实战工具 #10）
#
# 用法:
#   qygrep <关键词> <文件>       搜索单文件（退出码：有匹配 0，无匹配 1，出错 2）
#   qygrep -n <关键词> <文件>    显示行号
#   qygrep -c <关键词> <文件>    只输出匹配计数
#   qygrep -r <关键词> <目录>    递归搜索目录下所有普通文件
#
# 实战压测点：大文件分块 + 跨块断行、strstr 偏移语义、递归路径按深度分槽
# （不可重入陷阱）、退出码语义。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var fbuf: [65536] byte = 0;
var line: [4096] byte = 0;
var dir_names: [64000] byte = 0;
var dir_types: [250] byte = 0;
var paths: [7168] byte = 0;      # 7 槽 × 1024，递归路径按深度分槽
var lineno_buf: [16] byte = 0;
var cnt_buf: [24] byte = 0;
var pattern: [256] byte = 0;
var path_now: [1024] byte = 0;   # 当前文件名（输出前缀）

var show_line: i64 = 0;
var count_only: i64 = 0;
var path_show: i64 = 0;          # 输出时是否打印 path_now 前缀
var total: i64 = 0;
var cur_line: i64 = 0;

fn itoa10(v: i64, dst: i64) -> i64 {
    let t: [20] byte = 0;
    let d: i64 = 0;
    let x: i64 = v;
    if x == 0 { store8(&t, 48); d = 1; }
    while x > 0 {
        store8(&t + d, 48 + (x % 10));
        d = d + 1;
        x = x / 10;
    }
    let i: i64 = 0;
    while i < d {
        store8(dst + i, load8(&t + d - 1 - i));
        i = i + 1;
    }
    store8(dst + d, 0);
    return d;
}

# 扫描 fbuf 中 sz 字节的文本，逐行匹配 pattern
fn scan_text(sz: i64) -> i64 {
    let i: i64 = 0;
    let matches: i64 = 0;
    while i < sz {
        let l: i64 = 0;
        while i < sz && load8(&fbuf + i) != 10 {
            if l < 4090 {
                store8(&line + l, load8(&fbuf + i));
                l = l + 1;
            }
            i = i + 1;
        }
        i = i + 1;   # 跳过 \n
        store8(&line + l, 0);
        cur_line = cur_line + 1;
        if strstr(&line, &pattern) >= 0 {
            matches = matches + 1;
            total = total + 1;
            if count_only == 0 {
                if path_show == 1 {
                    print(&path_now);
                    print(":");
                }
                if show_line == 1 {
                    itoa10(cur_line, &lineno_buf);
                    print(&lineno_buf);
                    print(":");
                }
                print(&line);
                print("\n");
            }
        }
    }
    return matches;
}

# 搜索单个文件
fn grep_file(pth: i64) -> i64 {
    let sz: i64 = stat_size(pth);
    if sz < 0 {
        print("qygrep: 打不开: ");
        print(pth);
        print("\n");
        return 0 - 1;
    }
    let fd: i64 = fopen(pth, 0, 0);
    if fd < 0 { return 0 - 1; }
    cur_line = 0;
    let m: i64 = 0;
    if sz > 65000 {
        # 分块：块尾最后一个 \n 之后的内容挪到下一块块头
        let carry: i64 = 0;
        while 1 == 1 {
            let n: i64 = fread(fd, &fbuf + carry, 65000 - carry);
            if n <= 0 { break; }
            let end: i64 = carry + n;
            let cut: i64 = end;
            while cut > 0 && load8(&fbuf + cut - 1) != 10 { cut = cut - 1; }
            if cut == 0 {
                # 整块无换行：极端长行，直接按块处理（不无限攒）
                cut = end;
            }
            m = m + scan_text(cut);
            let rest: i64 = end - cut;
            memcpy(&fbuf, &fbuf + cut, rest);
            carry = rest;
        }
        if carry > 0 {
            m = m + scan_text(carry);
        }
    } else {
        let n: i64 = fread(fd, &fbuf, 65000);
        if n > 0 {
            m = scan_text(n);
        }
    }
    fclose(fd);
    if count_only == 1 && m > 0 {
        if path_show == 1 {
            print(&path_now);
            print(":");
        }
        itoa10(m, &cnt_buf);
        print(&cnt_buf);
        print("\n");
    }
    return m;
}

# 递归目录（路径按深度分槽，避免重入覆盖）
fn grep_dir(depth: i64) -> i64 {
    if depth > 5 { return 0; }
    let here: i64 = &paths + depth * 1024;
    let n: i64 = dir_list(here, &dir_names, &dir_types, 256, 249);
    if n < 0 { return 0; }
    let child: i64 = &paths + (depth + 1) * 1024;
    let i: i64 = 0;
    while i < n {
        let nm: i64 = &dir_names + i * 256;
        if streq(nm, ".") != 1 && streq(nm, "..") != 1 {
            strcpy(child, here);
            strcat(child, "/");
            strcat(child, nm);
            if load8(&dir_types + i) == 4 {
                grep_dir(depth + 1);
            } else {
                strcpy(&path_now, child);
                path_show = 1;
                grep_file(child);
            }
        }
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    let i: i64 = 1;
    let have_pat: i64 = 0;
    let recursive: i64 = 0;
    let target_at: i64 = 0;
    let have_target: i64 = 0;
    while i < argc() {
        let a: i64 = argv(i);
        if have_pat == 0 && have_target == 0 && load8(a) == 45 && load8(a + 1) != 0 {
            let j: i64 = 1;
            while load8(a + j) != 0 {
                if load8(a + j) == 110 { show_line = 1; }
                if load8(a + j) == 99 { count_only = 1; }
                if load8(a + j) == 114 { recursive = 1; }
                j = j + 1;
            }
        } else if have_pat == 0 {
            strcpy(&pattern, a);
            have_pat = 1;
        } else if have_target == 0 {
            target_at = i;
            have_target = 1;
        }
        i = i + 1;
    }
    if have_pat == 0 || have_target == 0 {
        print("用法: qygrep [-n] [-c] [-r] <关键词> <文件|目录>\n");
        return 2;
    }
    let target: i64 = argv(target_at);
    let st: i64 = stat_mode(target);
    if st < 0 {
        print("qygrep: 打不开: ");
        print(target);
        print("\n");
        return 2;
    }
    if (st & 61440) == 16384 {
        if recursive == 0 {
            print("qygrep: ");
            print(target);
            print(" 是目录（需要 -r）\n");
            return 2;
        }
        strcpy(&paths, target);   # depth 0 槽
        grep_dir(0);
    } else {
        path_show = 0;
        strcpy(&path_now, target);
        grep_file(target);
    }
    if total > 0 { return 0; }
    return 1;
}
