# expect: 55
# 用循环遍历数组：累加 1..10
var buf: [16] i64 = 0;

fn main() -> i64 {
    let i: i64 = 0;
    while i < 10 {
        buf[i] = i + 1;
        i = i + 1;
    }
    let s: i64 = 0;
    i = 0;
    while i < 10 {
        s = s + buf[i];
        i = i + 1;
    }
    return s;
}
