# sort —— 读入文件的所有行，按字典序排序后输出
#   用法: sort <文件名>
#   行内容原地留在 buf 里，排序只排「行首偏移」数组，
#   所以不需要真的搬动字符串
import "fs.mo";
import "io.mo";
import "str.mo";

var buf: [4096] i64 = 0;

# 行首偏移表：最多 256 行
var offs: [256] i64 = 0;

var nline: i64 = 0;

# 扫描 buf，把每行行首的偏移记进 offs
# 就地改写：把每个 '\n' 临时置 0，方便按字符串比较
fn split() -> i64 {
    let i: i64 = 0;
    let p: i64 = &buf;
    while load8(&buf + i) != 0 {
        if i == 0 {
            store64(&offs, 0);
            nline = 1;
        } else {
            if load8(&buf + i - 1) == 10 {
                store64(&offs + nline * 8, i);
                nline = nline + 1;
            }
        }
        i = i + 1;
    }
    return nline;
}

# 取第 k 行的字符串指针（末尾的换行会被临时改成 0）
fn line(k: i64) -> i64 {
    return &buf + load64(&offs + k * 8);
}

fn trim(p: i64) -> i64 {
    let i: i64 = 0;
    while load8(p + i) != 0 {
        if load8(p + i) == 10 {
            store8(p + i, 0);
            return i;
        }
        i = i + 1;
    }
    return i;
}

# 对 offs[0..n) 做冒泡排序，比较的是行内容
fn sort_lines(n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let j: i64 = 0;
        while j < n - 1 - i {
            let a: i64 = line(j);
            let b: i64 = line(j + 1);
            if strcmp(a, b) > 0 {
                let ta: i64 = load64(&offs + j * 8);
                store64(&offs + j * 8, load64(&offs + (j + 1) * 8));
                store64(&offs + (j + 1) * 8, ta);
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("usage: sort <file>\n");
        return 2;
    }
    let n: i64 = read_file(argv(1), &buf, 16384);
    if n < 0 {
        print("sort: cannot open ");
        print(argv(1));
        print_nl();
        return 1;
    }
    split();
    # 把每行末尾的换行改成 0，这样 strcmp / print 都好处理
    let i: i64 = 0;
    while i < nline {
        trim(line(i));
        i = i + 1;
    }
    sort_lines(nline);
    i = 0;
    while i < nline {
        fputs(line(i));
        print_nl();
        i = i + 1;
    }
    return 0;
}
