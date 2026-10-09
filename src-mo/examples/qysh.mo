# qysh —— 类 shell 命令解释器（墨语言实战工具 #16）
#
# 墨语言迄今最复杂实战程序：综合压测 map/vec/str/fs/dir/pty 全部核心库。
#
# 功能：
#   - 命令分词（空格/Tab，引号保留字面）
#   - 多级管道 cmd1 | cmd2 | cmd3（pipe+dup2+fork+execve+waitpid）
#   - 内置命令：cd / pwd / echo / export / env / exit / history
#   - 环境变量表（map.mo 哈希表）与 $VAR 展开
#   - 外部命令沿 PATH 查找
#   - history 环形记录（最近 32 条）
#
# 非目标（受语言边界限制）：无信号作业控制、无脚本文件、无重定向。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";
import "map.mo";
import "vec.mo";
import "pty.mo";
import "net.mo";
import "mem.mo";

var line: [4096] byte = 0;
var tok: [256] byte = 0;
var pathbuf: [1024] byte = 0;
var pbuf: [1024] byte = 0;
var nbuf: [24] byte = 0;
var outbuf: [4096] byte = 0;
var pipe_rd: i64 = 0;
var pipe_wr: i64 = 0;

var myenv: i64 = 0;       # map: name -> value
var hist: [8192] byte = 0;   # 32 条 × 256
var hist_n: i64 = 0;
var hist_i: i64 = 0;

var tokens: [16384] byte = 0;   # 64 段 × 256
var tokn: i64 = 0;

# 每个管道段的 argv 下标范围
var seg_start: [16] i64 = 0;
var seg_end: [16] i64 = 0;
var segn: i64 = 0;

# ---- 标准库暂缺的系统调用封装（后续回填 fs.mo/net.mo）----
fn sys_read(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(0, fd, buf, n, 0, 0, 0);
}
fn sys_close(fd: i64) -> i64 {
    return syscall(3, fd, 0, 0, 0, 0, 0);
}
fn sys_pipe(pfd: i64) -> i64 {
    return syscall(22, pfd, 0, 0, 0, 0, 0);
}
fn sys_dup2(old: i64, new: i64) -> i64 {
    return syscall(33, old, new, 0, 0, 0, 0);
}
fn sys_chdir(p: i64) -> i64 {
    return syscall(80, p, 0, 0, 0, 0, 0);
}
fn sys_getcwd(buf: i64, n: i64) -> i64 {
    return syscall(79, buf, n, 0, 0, 0, 0);
}

fn is_space(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 9 { return 1; }
    return 0;
}

# 分词：按空格切分，双引号包裹保留；同时直接切分管道段
# 产出 tokens[0..tokn) 与 seg_start/seg_end（段号 segn 个）
fn tokenize(s: i64) -> i64 {
    tokn = 0;
    segn = 0;
    let i: i64 = 0;
    let n: i64 = strlen(s);
    seg_start[0] = 0;
    while i < n {
        while i < n && is_space(load8(s + i)) == 1 { i = i + 1; }
        if i >= n { break; }
        # 若当前字符就是 '|' → 结束本段，开新段
        if load8(s + i) == 124 {
            seg_end[segn] = tokn;
            segn = segn + 1;
            if segn < 15 { seg_start[segn] = tokn; }
            i = i + 1;
            continue;
        }
        let t: i64 = &tokens + tokn * 256;
        let l: i64 = 0;
        let in_q: i64 = 0;
        while i < n {
            let c: i64 = load8(s + i);
            if in_q == 1 {
                if c == 34 { in_q = 0; i = i + 1; continue; }
            } else {
                if c == 34 { in_q = 1; i = i + 1; continue; }
                if is_space(c) == 1 { break; }
                if c == 124 { break; }
            }
            if l < 250 { store8(t + l, c); l = l + 1; }
            i = i + 1;
        }
        store8(t + l, 0);
        tokn = tokn + 1;
    }
    seg_end[segn] = tokn;
    return tokn;
}

# $VAR 展开（只支持到下一个非 [A-Za-z0-9_] 字符）
fn expand(src: i64, dst: i64) -> i64 {
    let i: i64 = 0;
    let l: i64 = 0;
    let n: i64 = strlen(src);
    while i < n {
        let c: i64 = load8(src + i);
        if c == 36 && i + 1 < n {   # '$'
            let j: i64 = i + 1;
            let name: [64] byte = 0;
            let nl: i64 = 0;
            while j < n {
                let d: i64 = load8(src + j);
                if (d >= 65 && d <= 90) || (d >= 97 && d <= 122) || (d >= 48 && d <= 57) || d == 95 {
                    if nl < 60 { store8(&name + nl, d); nl = nl + 1; }
                    j = j + 1;
                } else { break; }
            }
            store8(&name + nl, 0);
            if nl > 0 {
                if map_has(myenv, &name) == 1 {
                    let v: i64 = map_get(myenv, &name);
                    let vl: i64 = strlen(v);
                    let k: i64 = 0;
                    while k < vl && l < 1000 {
                        store8(dst + l, load8(v + k));
                        l = l + 1;
                        k = k + 1;
                    }
                }
                i = j;
                continue;
            }
        }
        if l < 1000 { store8(dst + l, c); l = l + 1; }
        i = i + 1;
    }
    store8(dst + l, 0);
    return 0;
}

fn push_hist(s: i64) -> i64 {
    strcpy(&hist + hist_i * 256, s);
    hist_i = (hist_i + 1) & 31;
    if hist_n < 32 { hist_n = hist_n + 1; }
    return 0;
}

# 在 PATH 里找可执行文件
fn find_in_path(name: i64, dst: i64) -> i64 {
    # 含 / 直接用
    if strstr(name, "/") >= 0 {
        strcpy(dst, name);
        return 0;
    }
    let pathv: i64 = map_get(myenv, "PATH");
    if pathv == 0 || strlen(pathv) == 0 {
        strcpy(dst, name);
        return 0;
    }
    let i: i64 = 0;
    let n: i64 = strlen(pathv);
    let seg: [256] byte = 0;
    while i <= n {
        let l: i64 = 0;
        while i < n && load8(pathv + i) != 58 {
            if l < 250 { store8(&seg + l, load8(pathv + i)); l = l + 1; }
            i = i + 1;
        }
        store8(&seg + l, 0);
        if l > 0 {
            strcpy(dst, &seg);
            strcat(dst, "/");
            strcat(dst, name);
            if stat_mode(dst) >= 0 { return 0; }
        }
        i = i + 1;
    }
    strcpy(dst, name);
    return 0 - 1;
}

# 执行一段（argv 区间 [a,b)），输入 in_fd，输出 out_fd
# 返回退出码
fn run_segment(a: i64, b: i64, in_fd: i64, out_fd: i64) -> i64 {
    if b <= a { return 0; }
    let cmd: i64 = &tokens + a * 256;
    # ---- 内置命令 ----
    if streq(cmd, "cd") == 1 {
        if b > a + 1 {
            sys_chdir(&tokens + (a + 1) * 256);
        } else {
            let h: i64 = map_get(myenv, "HOME");
            if h != 0 { sys_chdir(h); }
        }
        return 0;
    }
    if streq(cmd, "pwd") == 1 {
        sys_getcwd(&pbuf, 1000);
        print(&pbuf);
        print("\n");
        return 0;
    }
    if streq(cmd, "echo") == 1 {
        let k: i64 = a + 1;
        let first: i64 = 1;
        while k < b {
            if first != 1 { print(" "); }
            print(&tokens + k * 256);
            first = 0;
            k = k + 1;
        }
        print("\n");
        return 0;
    }
    if streq(cmd, "export") == 1 {
        if b > a + 1 {
            let kv: i64 = &tokens + (a + 1) * 256;
            let eq: i64 = strstr(kv, "=");
            if eq > 0 {
                let name: [64] byte = 0;
                memcpy(&name, kv, eq);
                store8(&name + eq, 0);
                map_put(myenv, &name, kv + eq + 1);
            }
        }
        return 0;
    }
    if streq(cmd, "env") == 1 {
        # 简化：打印我们知道的几个
        print("PATH=");
        print(map_get(myenv, "PATH"));
        print("\nHOME=");
        print(map_get(myenv, "HOME"));
        print("\n");
        return 0;
    }
    if streq(cmd, "exit") == 1 {
        return 0 - 1000;   # 特殊值：退出 shell
    }
    if streq(cmd, "history") == 1 {
        let k: i64 = 0;
        let base: i64 = hist_i - hist_n;
        while k < hist_n {
            let idx: i64 = (base + k) & 31;
            if idx < 0 { idx = idx + 32; }
            print_i64(k + 1);
            print(" ");
            print(&hist + idx * 256);
            print("\n");
            k = k + 1;
        }
        return 0;
    }
    # ---- 外部命令：fork + execve ----
    find_in_path(cmd, &pathbuf);
    let pid: i64 = fork();
    if pid == 0 {
        # 子进程：接管道
        if in_fd != 0 { sys_dup2(in_fd, 0); }
        if out_fd != 1 { sys_dup2(out_fd, 1); }
        # 组 argv（连续指针数组）
        let argv_arr: [64] i64 = 0;
        let k: i64 = 0;
        while k < b - a {
            argv_arr[k] = &tokens + (a + k) * 256;
            k = k + 1;
        }
        argv_arr[b - a] = 0;
        # envp：极简两项目录
        let envp: [3] i64 = 0;
        execve(&pathbuf, &argv_arr, &envp);
        print("qysh: 找不到命令: ");
        print(cmd);
        print("\n");
        exit(127);
    }
    waitpid(pid);
    return 0;
}

# 执行整行（可能是多级管道）
fn exec_line(s: i64) -> i64 {
    tokenize(s);
    if tokn == 0 { return 0; }
    if segn == 0 {
        let rc: i64 = run_segment(seg_start[0], seg_end[0], 0, 1);
        return rc;
    }
    # 多级管道
    let prev_rd: i64 = 0;
    let i: i64 = 0;
    let rc: i64 = 0;
    while i <= segn {
        let is_last: i64 = 0;
        if i == segn { is_last = 1; }
        let w_fd: i64 = 1;
        if is_last != 1 {
            if sys_pipe(&pipe_rd) != 0 {
                print("qysh: pipe 失败\n");
                return 0 - 1;
            }
            # pipe 写两个 int（各 4 字节）：rd 在低 4 字节、wr 在高 4 字节
            pipe_wr = load8(&pipe_rd + 4) + load8(&pipe_rd + 5) * 256 + load8(&pipe_rd + 6) * 65536 + load8(&pipe_rd + 7) * 16777216;
            w_fd = pipe_wr;
        }
        rc = run_segment(seg_start[i], seg_end[i], prev_rd, w_fd);
        if rc == 0 - 1000 { return rc; }
        if is_last != 1 {
            # 关写端（父进程），留读端给下一段
            prev_rd = load8(&pipe_rd) + load8(&pipe_rd + 1) * 256 + load8(&pipe_rd + 2) * 65536 + load8(&pipe_rd + 3) * 16777216;
            if w_fd > 1 { sys_close(w_fd); }
        }
        i = i + 1;
    }
    return rc;
}

# 读一行（无 readline：逐字符 read，退格处理）
fn read_line(dst: i64) -> i64 {
    let l: i64 = 0;
    while 1 == 1 {
        let c: [1] byte = 0;
        let n: i64 = sys_read(0, &c, 1);
        if n <= 0 { store8(dst, 0); return 0 - 1; }   # EOF
        let ch: i64 = load8(&c);
        if ch == 10 { break; }
        if ch == 127 || ch == 8 {
            if l > 0 { l = l - 1; }
            continue;
        }
        if l < 4000 {
            store8(dst + l, ch);
            l = l + 1;
        }
    }
    store8(dst + l, 0);
    return l;
}

fn init_env() -> i64 {
    heap_init();
    myenv = map_new();
    # 从真实 environ 简化：塞几个常用默认
    map_put(myenv, "PATH", "/bin:/usr/bin:/sbin");
    map_put(myenv, "HOME", "/root");
    return 0;
}

fn main() -> i64 {
    init_env();
    print("qysh 1.0 (mo) —— 输入命令，exit 退出\n");
    while 1 == 1 {
        print("qysh> ");
        if read_line(&line) < 0 { break; }
        if strlen(&line) == 0 { continue; }
        push_hist(&line);
        let exp: [1024] byte = 0;
        expand(&line, &exp);
        let rc: i64 = exec_line(&exp);
        if rc == 0 - 1000 { break; }
    }
    print("bye\n");
    return 0;
}
