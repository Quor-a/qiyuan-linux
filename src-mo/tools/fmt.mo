# fmt —— 墨语言源码格式化工具（用墨语言自己写的）
#
#   fmt <file>         格式化结果输出到 stdout
#   fmt -w <file>      就地写回文件
#
# 只调整「空白」：缩进、行尾空格、确保末尾有换行。
# 不增删行、不重排代码、不动注释与字符串的内容。
# 因此格式化前后是同一串 token —— 编译产出的代码段应逐字节相同。
import "io.mo";
import "fs.mo";

var inbuf:  [262144] byte = 0;
var outbuf: [262144] byte = 0;

fn is_ws(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 9 { return 1; }
    return 0;
}

# 格式化：src[0..n) -> dst，返回写出的字节数
fn fmt(src: ptr, n: i64, dst: ptr) -> i64 {
    let i: i64 = 0;
    let o: i64 = 0;
    let depth: i64 = 0;
    while i < n {
        # 找行尾（\n 或末尾）
        let e: i64 = i;
        while e < n {
            if src[e] == 10 { break; }
            e = e + 1;
        }
        # 去掉前导空白
        let s: i64 = i;
        while s < e {
            if is_ws(src[s]) == 0 { break; }
            s = s + 1;
        }
        # 去掉行尾空白
        let t: i64 = e;
        while t > s {
            if is_ws(src[t - 1]) == 0 { break; }
            t = t - 1;
        }
        # 缩进：以 '}' 开头的行先收一级
        let ind: i64 = depth;
        if s < t {
            if src[s] == 125 { ind = depth - 1; }
        }
        if ind < 0 { ind = 0; }
        let k: i64 = 0;
        while k < ind * 4 {
            dst[o] = 32;
            o = o + 1;
            k = k + 1;
        }
        # 输出本行内容，同时按括号调整 depth。
        # 字符串、字符字面量、注释里的括号不参与计数。
        let j: i64 = s;
        while j < t {
            let c: i64 = src[j];
            if c == 34 {
                # 字符串：原样输出直到闭合引号（支持 \ 转义）
                dst[o] = c; o = o + 1;
                j = j + 1;
                while j < t {
                    if src[j] == 92 {
                        dst[o] = src[j]; o = o + 1;
                        if j + 1 < t {
                            dst[o] = src[j + 1]; o = o + 1;
                            j = j + 2;
                        } else {
                            j = j + 1;
                        }
                    } else {
                        dst[o] = src[j]; o = o + 1;
                        if src[j] == 34 { j = j + 1; break; }
                        j = j + 1;
                    }
                }
            } else {
                if c == 39 {
                    # 字符字面量
                    dst[o] = c; o = o + 1;
                    j = j + 1;
                    while j < t {
                        if src[j] == 92 {
                            dst[o] = src[j]; o = o + 1;
                            if j + 1 < t {
                                dst[o] = src[j + 1]; o = o + 1;
                                j = j + 2;
                            } else {
                                j = j + 1;
                            }
                        } else {
                            dst[o] = src[j]; o = o + 1;
                            if src[j] == 39 { j = j + 1; break; }
                            j = j + 1;
                        }
                    }
                } else {
                    if c == 35 {
                        # 注释：本行剩余部分原样输出，不参与括号计数
                        while j < t {
                            dst[o] = src[j]; o = o + 1;
                            j = j + 1;
                        }
                    } else {
                        if c == 123 { depth = depth + 1; }
                        else {
                            if c == 125 { depth = depth - 1; }
                        }
                        dst[o] = c; o = o + 1;
                        j = j + 1;
                    }
                }
            }
        }
        if depth < 0 { depth = 0; }
        dst[o] = 10;
        o = o + 1;
        i = e + 1;
    }
    return o;
}

fn main() -> i64 {
    let w: i64 = 0;
    let path: i64 = "";
    let ai: i64 = 1;
    while ai < argc() {
        let a: i64 = argv(ai);
        if streq(a, "-w") == 1 {
            w = 1;
        } else {
            path = a;
        }
        ai = ai + 1;
    }
    if streq(path, "") == 1 {
        print("usage: fmt [-w] <file>\n");
        return 2;
    }
    let n: i64 = read_file(path, &inbuf, 262144);
    if n < 0 {
        print("fmt: cannot open ");
        print(path);
        print_nl();
        return 1;
    }
    let m: i64 = fmt(&inbuf, n, &outbuf);
    outbuf[m] = 0;
    if w == 1 {
        let fd: i64 = fopen(path, 577, 420);
        if fd < 0 {
            print("fmt: cannot write ");
            print(path);
            print_nl();
            return 1;
        }
        fwrite(fd, &outbuf, m);
        fclose(fd);
        return 0;
    }
    fputs(&outbuf);
    return 0;
}
