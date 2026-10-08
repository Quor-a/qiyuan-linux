# grep —— 在文件中查找含指定子串的行
#   用法: grep <子串> <文件名>
#   只做固定子串匹配，不做正则
import "fs.mo";
import "io.mo";
import "str.mo";

var buf: [4096] i64 = 0;

var nline: i64 = 0;
var nhit: i64 = 0;

# 在「一行」里找 pat：找到返回起始下标，找不到返回 -1
# 关键：碰到 '\n' 必须停下，否则会跨行匹配到下一行的开头
fn find(s: i64, pat: i64) -> i64 {
    let plen: i64 = strlen(pat);
    if plen == 0 { return 0; }
    let i: i64 = 0;
    while load8(s + i) != 0 {
        if load8(s + i) == 10 {
            return -1;
        }
        let j: i64 = 0;
        let ok: i64 = 1;
        while j < plen {
            if load8(s + i + j) != load8(pat + j) {
                ok = 0;
                break;
            }
            j = j + 1;
        }
        if ok == 1 {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

# 打印一行（含末尾换行），返回前进的字节数
fn emit_line(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        if load8(s + i) == 10 {
            i = i + 1;
            break;
        }
        i = i + 1;
    }
    syscall(1, 1, s, i, 0, 0, 0);
    return i;
}

# 跳到下一行开头；已在末尾则返回 -1
fn next_line(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        if load8(s + i) == 10 {
            return s + i + 1;
        }
        i = i + 1;
    }
    return -1;
}

fn main() -> i64 {
    if argc() < 3 {
        print("usage: grep <pattern> <file>\n");
        return 2;
    }
    let n: i64 = read_file(argv(2), &buf, 16384);
    if n < 0 {
        print("grep: cannot open ");
        print(argv(2));
        print_nl();
        return 1;
    }
    let p: i64 = &buf;
    let done: i64 = 0;
    while done == 0 {
        nline = nline + 1;
        if find(p, argv(1)) >= 0 {
            nhit = nhit + 1;
            emit_line(p);
        }
        let q: i64 = next_line(p);
        if q < 0 {
            done = 1;
        } else {
            p = q;
        }
        if load8(p) == 0 {
            done = 1;
        }
    }
    print_i64(nhit);
    print(" / ");
    print_i64(nline);
    print(" lines matched\n");
    return 0;
}
