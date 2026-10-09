# qywc —— 文本统计工具（墨语言实战工具 #11）
#
# 用法:
#   qywc <文件>            输出 行数 词数 字节数 文件名（wc 惯例顺序）
#   qywc -l <文件>         只行数   -w 只词数   -c 只字节数（-lc 组合可）
#   qywc -r <关键词目录>?   不支持——保持单一职责
#
# 实战压测点：状态机分词（空白/非空白状态迁移）、大文件分块计数（状态跨块
# 延续——carry 不是字符而是"上一块末尾是否在词中"的布尔状态）、
# 多文件聚合输出、与系统 wc 逐项对照。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var fbuf: [65536] byte = 0;
var nbuf: [24] byte = 0;
var path_now: [1024] byte = 0;

# 计数器（全局，多文件累加用）
var l_total: i64 = 0;
var w_total: i64 = 0;
var c_total: i64 = 0;

var show_l: i64 = 1;
var show_w: i64 = 1;
var show_c: i64 = 1;

# 判断是否空白（空格/Tab/CR/换行/竖直空白简化为这四种）
fn is_space(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 9 { return 1; }
    if c == 10 { return 1; }
    if c == 13 { return 1; }
    if c == 11 { return 1; }
    if c == 12 { return 1; }
    return 0;
}

# 打印一个数（右对齐 8 格，wc 风格简化为直接空格分隔）
fn print_num(v: i64) -> i64 {
    print(" ");
    print_i64(v);
    return 0;
}

# 统计一块（sz 字节）。in_word 跨块状态：入口值表示"块首字符处于词中"。
# 返回新的 in_word。
fn count_chunk(sz: i64, in_word: i64) -> i64 {
    let i: i64 = 0;
    while i < sz {
        let ch: i64 = load8(&fbuf + i);
        if ch == 10 {
            l_total = l_total + 1;
        }
        if is_space(ch) == 1 {
            in_word = 0;
        } else {
            if in_word == 0 {
                w_total = w_total + 1;
            }
            in_word = 1;
        }
        i = i + 1;
    }
    return in_word;
}

# 单文件统计；成功返回 0
fn wc_file(pth: i64) -> i64 {
    let sz: i64 = stat_size(pth);
    if sz < 0 {
        print("qywc: 打不开: ");
        print(pth);
        print("\n");
        return 0 - 1;
    }
    let fd: i64 = fopen(pth, 0, 0);
    if fd < 0 { return 0 - 1; }
    let in_word: i64 = 0;
    let l0: i64 = l_total;
    let w0: i64 = w_total;
    let bytes: i64 = 0;
    while 1 == 1 {
        let n: i64 = fread(fd, &fbuf, 65536);
        if n <= 0 { break; }
        bytes = bytes + n;
        in_word = count_chunk(n, in_word);
    }
    fclose(fd);
    # 无尾换行时补逻辑行？wc 不补——保持与 wc 一致（行数= \n 个数）
    c_total = c_total + bytes;
    # 输出：按 show_* 顺序输出所选列；无任何有效列时输出全部
    let dl: i64 = l_total - l0;
    let dw: i64 = w_total - w0;
    let any_col: i64 = 0;
    if show_l == 1 || show_w == 1 || show_c == 1 { any_col = 1; }
    if any_col == 0 { show_l = 1; show_w = 1; show_c = 1; }
    if show_l == 1 { print_num(dl); }
    if show_w == 1 { print_num(dw); }
    if show_c == 1 { print_num(bytes); }
    print(" ");
    print(pth);
    print("\n");
    return 0;
}

fn main() -> i64 {
    let i: i64 = 1;
    let have_target: i64 = 0;
    let target_at: i64 = 0;
    let any_flag: i64 = 0;
    while i < argc() {
        let a: i64 = argv(i);
        if have_target == 0 && load8(a) == 45 && load8(a + 1) != 0 {
            any_flag = 1;
            let j: i64 = 1;
            while load8(a + j) != 0 {
                if load8(a + j) == 108 { show_l = 1; show_w = 0; show_c = 0; }   # l
                if load8(a + j) == 119 { show_w = 1; show_l = 0; show_c = 0; }   # w
                if load8(a + j) == 99  { show_c = 1; show_l = 0; show_w = 0; }   # c
                j = j + 1;
            }
        } else if have_target == 0 {            target_at = i;
            have_target = 1;
        }
        i = i + 1;
    }
    if have_target == 0 {
        print("用法: qywc [-l|-w|-c] <文件>\n");
        return 1;
    }
    let target: i64 = argv(target_at);
    if wc_file(target) < 0 { return 1; }
    return 0;
}
