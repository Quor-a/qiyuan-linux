# expect: 0
# 排序：验证 strcmp 的三种结果与冒泡排序
import "io.mo";
import "str.mo";

# 起 5 个字符串，排序后应为 a e i o u
var s0: [8] i64 = 0;
var s1: [8] i64 = 0;
var s2: [8] i64 = 0;
var s3: [8] i64 = 0;
var s4: [8] i64 = 0;

var idx: [5] i64 = 0;

fn setall() -> i64 {
    strcpy(&s0, "u");
    strcpy(&s1, "a");
    strcpy(&s2, "o");
    strcpy(&s3, "e");
    strcpy(&s4, "i");
    store64(&idx, 0);
    store64(&idx + 8, 1);
    store64(&idx + 16, 2);
    store64(&idx + 24, 3);
    store64(&idx + 32, 4);
    return 0;
}

fn at(k: i64) -> i64 {
    let i: i64 = load64(&idx + k * 8);
    if i == 0 { return &s0; }
    if i == 1 { return &s1; }
    if i == 2 { return &s2; }
    if i == 3 { return &s3; }
    return &s4;
}

fn sort5() -> i64 {
    let i: i64 = 0;
    while i < 5 {
        let j: i64 = 0;
        while j < 4 - i {
            if strcmp(at(j), at(j + 1)) > 0 {
                let t: i64 = load64(&idx + j * 8);
                store64(&idx + j * 8, load64(&idx + (j + 1) * 8));
                store64(&idx + (j + 1) * 8, t);
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    setall();
    sort5();
    let i: i64 = 0;
    while i < 5 {
        print(at(i));
        i = i + 1;
    }
    print_nl();
    return 0;
}
