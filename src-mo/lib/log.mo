# log —— 完整日志框架（用墨语言自己写的）
#
# 设计目标（这轮重写的重点）：
#   1. 多 sink：stderr / 文件 / 环形缓冲 / 丢弃，可同时开多个
#   2. 结构化字段：log_kv("user","mo") 累积到当前记录，输出 key=value
#   3. 时间戳：单调时钟（启动后毫秒）+ 墙上时钟（秒，来自 clock_gettime）
#   4. 模块名：每条记录带 logger 名，便于按来源过滤
#   5. 滚动：文件超过 LOG_MAX 就切成 .1，重新开一个
#   6. 级别：TRACE < DEBUG < INFO < WARN < ERROR < FATAL
#   7. 阈值可运行时调整；FATAL 记录后可选立即退出
#
# 与 1.5.0 版的差异：旧版只有「级别 + 环形缓冲」，没有 sink / 字段 / 滚动 / 模块名。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

# 级别
var L_TRACE: i64 = 0;
var L_DEBUG: i64 = 1;
var L_INFO: i64 = 2;
var L_WARN: i64 = 3;
var L_ERROR: i64 = 4;
var L_FATAL: i64 = 5;

var LOG_LEVEL: i64 = 2;        # 低于这条不输出
var LOG_NAME: [32] byte = 0;   # logger 名（模块名）

# sink 开关
var SINK_ERR: i64 = 1;         # 写 stderr
var SINK_FILE: i64 = 0;        # 写文件
var SINK_RING: i64 = 1;        # 写环形缓冲

var LOG_FD: i64 = 0;
var LOG_PATH: [128] byte = 0;
var LOG_MAX: i64 = 262144;     # 单文件上限，超过就滚动
var LOG_SIZE: i64 = 0;

# 环形缓冲：保留最近 32 条
var RING: [32] i64 = 0;
var RING_N: i64 = 0;
var RING_I: i64 = 0;
var rbuf: [8192] byte = 0;
var rpos: i64 = 0;

# 当前记录的结构化字段
var kvbuf: [512] byte = 0;

# 计数（便于测试与自检）
var N_EMIT: i64 = 0;
var N_DROP: i64 = 0;

# ---------- 时间 ----------

var TSB: [2] i64 = 0;
# 启动后的毫秒（CLOCK_MONOTONIC = 1）
fn now_ms() -> i64 {
    let r: i64 = syscall(228, 1, &TSB, 0, 0, 0, 0);
    if r < 0 { return 0; }
    return load64(&TSB) * 1000 + load64(&TSB + 8) / 1000000;
}
# 墙上时钟秒（CLOCK_REALTIME = 0）
fn now_sec() -> i64 {
    let r: i64 = syscall(228, 0, &TSB, 0, 0, 0, 0);
    if r < 0 { return 0; }
    return load64(&TSB);
}

# ---------- 配置 ----------

fn log_set_level(l: i64) -> i64 { LOG_LEVEL = l; return 0; }
fn log_get_level() -> i64 { return LOG_LEVEL; }

fn log_set_name(n: i64) -> i64 {
    strcpy(&LOG_NAME, n);
    return 0;
}

fn log_sink(err: i64, fil: i64, ring: i64) -> i64 {
    SINK_ERR = err;
    SINK_FILE = fil;
    SINK_RING = ring;
    return 0;
}

fn log_open(path: i64) -> i64 {
    LOG_FD = fopen(path, 577, 420);
    if LOG_FD < 0 { return -1; }
    strcpy(&LOG_PATH, path);
    LOG_SIZE = 0;
    SINK_FILE = 1;
    return 0;
}

fn log_close() -> i64 {
    if LOG_FD > 0 {
        fclose(LOG_FD);
        LOG_FD = 0;
        SINK_FILE = 0;
    }
    return 0;
}

# ---------- 滚动 ----------

fn log_rotate() -> i64 {
    if LOG_FD <= 0 { return -1; }
    fclose(LOG_FD);
    let old: [160] byte = 0;
    strcpy(&old, &LOG_PATH);
    strcat(&old, ".1");
    # 直接把当前内容整体读出再写入 .1（没有 rename 语义的封装时用复制更稳）
    let n: i64 = stat_size(&LOG_PATH);
    if n > 0 {
        let buf: [65536] byte = 0;
        let m: i64 = read_file(&LOG_PATH, &buf, 65535);
        if m > 0 {
            let w: i64 = fopen(&old, 577, 420);
            if w > 0 {
                fwrite(w, &buf, m);
                fclose(w);
            }
        }
    }
    # 截断原文件重新写
    let w2: i64 = fopen(&LOG_PATH, 577, 420);
    if w2 < 0 { return -1; }
    LOG_FD = w2;
    LOG_SIZE = 0;
    return 0;
}

# ---------- 记录构造 ----------

var line: [640] byte = 0;

fn kv_reset() -> i64 {
    store8(&kvbuf, 0);
    return 0;
}

# 追加一个结构化字段：key=value
fn log_kv(k: i64, v: i64) -> i64 {
    if strlen(&kvbuf) > 0 { strcat(&kvbuf, " "); }
    strcat(&kvbuf, k);
    strcat(&kvbuf, "=");
    strcat(&kvbuf, v);
    return 0;
}

fn log_kvi(k: i64, v: i64) -> i64 {
    let b: [24] byte = 0;
    utoa(v, &b, 10);
    return log_kv(k, &b);
}

fn level_name(l: i64) -> i64 {
    if l == 0 { return "TRACE"; }
    if l == 1 { return "DEBUG"; }
    if l == 2 { return "INFO"; }
    if l == 3 { return "WARN"; }
    if l == 4 { return "ERROR"; }
    return "FATAL";
}

# 组装一行：[ms] LEVEL name msg k=v k=v
fn build(l: i64, msg: i64) -> i64 {
    store8(&line, 0);
    strcat(&line, "[");
    let tb: [24] byte = 0;
    utoa(now_ms(), &tb, 10);
    strcat(&line, &tb);
    strcat(&line, "ms ");
    utoa(now_sec(), &tb, 10);
    strcat(&line, &tb);
    strcat(&line, "] ");
    strcat(&line, level_name(l));
    strcat(&line, " ");
    if strlen(&LOG_NAME) > 0 {
        strcat(&line, &LOG_NAME);
        strcat(&line, ": ");
    }
    strcat(&line, msg);
    if strlen(&kvbuf) > 0 {
        strcat(&line, "  {");
        strcat(&line, &kvbuf);
        strcat(&line, "}");
    }
    strcat(&line, "\n");
    kv_reset();
    return 0;
}

fn ring_push(s: i64) -> i64 {
    let n: i64 = strlen(s);
    if rpos + n + 1 > 8192 { rpos = 0; }
    let off: i64 = rpos;
    strcpy(&rbuf + off, s);
    rpos = rpos + n + 1;
    RING[RING_I] = off;
    RING_I = (RING_I + 1) & 31;
    if RING_N < 32 { RING_N = RING_N + 1; }
    return 0;
}

fn emit(l: i64, msg: i64) -> i64 {
    if l < LOG_LEVEL { N_DROP = N_DROP + 1; kv_reset(); return 0; }
    build(l, msg);
    N_EMIT = N_EMIT + 1;
    let n: i64 = strlen(&line);
    if SINK_ERR == 1 { syscall(1, 2, &line, n, 0, 0, 0); }
    if SINK_RING == 1 { ring_push(&line); }
    if SINK_FILE == 1 {
        if LOG_FD > 0 {
            if LOG_SIZE + n > LOG_MAX { log_rotate(); }
            fwrite(LOG_FD, &line, n);
            LOG_SIZE = LOG_SIZE + n;
        }
    }
    return 0;
}

fn log_trace(m: i64) -> i64 { return emit(L_TRACE, m); }
fn log_debug(m: i64) -> i64 { return emit(L_DEBUG, m); }
fn log_info(m: i64)  -> i64 { return emit(L_INFO, m); }
fn log_warn(m: i64)  -> i64 { return emit(L_WARN, m); }
fn log_error(m: i64) -> i64 { return emit(L_ERROR, m); }
fn log_fatal(m: i64) -> i64 { return emit(L_FATAL, m); }

# ---------- 读取 ----------

# 回看最近 n 条（写到 stderr）；返回实际条数
fn log_tail(n: i64) -> i64 {
    if n > RING_N { n = RING_N; }
    if n <= 0 { return 0; }
    let i: i64 = 0;
    while i < n {
        let idx: i64 = (RING_I - n + i) & 31;
        if idx < 0 { idx = idx + 32; }
        let s: i64 = &rbuf + RING[idx];
        syscall(1, 2, s, strlen(s), 0, 0, 0);
        i = i + 1;
    }
    return n;
}

# 按级别过滤回看（level 为最低级别）
fn log_since(level: i64) -> i64 {
    let cnt: i64 = 0;
    let i: i64 = 0;
    while i < RING_N {
        let idx: i64 = (RING_I - RING_N + i) & 31;
        if idx < 0 { idx = idx + 32; }
        let s: i64 = &rbuf + RING[idx];
        # 级别名在 "] " 之后
        let p: i64 = strstr(s, "] ");
        if p >= 0 {
            let q: i64 = p + 2;
            let l: i64 = 0;
            if load8(s + q) == 84 { l = 0; }                     # T
            else {
                if load8(s + q) == 68 { l = 1; }                 # D
                else {
                    if load8(s + q) == 73 { l = 2; }              # I
                    else {
                        if load8(s + q) == 87 { l = 3; }          # W
                        else {
                            if load8(s + q) == 69 { l = 4; }      # E
                            else { l = 5; }                       # F
                        }
                    }
                }
            }
            if l >= level {
                syscall(1, 2, s, strlen(s), 0, 0, 0);
                cnt = cnt + 1;
            }
        }
        i = i + 1;
    }
    return cnt;
}

fn log_stats() -> i64 {
    return N_EMIT * 1000 + N_DROP;
}
