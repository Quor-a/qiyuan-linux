# wc —— 统计文件的行数、词数、字符数
#   用法: wc <文件名>
#   不给参数时统计一段内建文本
import "fs.mo";
import "io.mo";
import "str.mo";

var lines: i64 = 0;
var words: i64 = 0;
var chars: i64 = 0;
var inword: i64 = 0;

var buf: [4096] i64 = 0;

fn is_space(c: i64) -> i64 {
    if c == 32 { return 1; }
    if c == 10 { return 1; }
    if c == 9 { return 1; }
    return 0;
}

fn count(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        let c: i64 = load8(s + i);
        chars = chars + 1;
        if c == 10 {
            lines = lines + 1;
        }
        if is_space(c) == 1 {
            inword = 0;
        } else {
            if inword == 0 {
                words = words + 1;
            }
            inword = 1;
        }
        i = i + 1;
    }
    return i;
}

fn main() -> i64 {
    if argc() < 2 {
        count("hello mo world\nthis is line two\n");
        report();
        return 0;
    }
    let n: i64 = read_file(argv(1), &buf, 16384);
    if n < 0 {
        print("wc: cannot open ");
        print(argv(1));
        print_nl();
        return 1;
    }
    count(&buf);
    report();
    return 0;
}

fn report() -> i64 {
    print_i64(lines);
    print(" lines, ");
    print_i64(words);
    print(" words, ");
    print_i64(chars);
    print(" chars\n");
    return 0;
}
