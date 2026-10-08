# expect: 30
# continue：只累加 1..10 中的偶数
fn main() -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 10 {
        i = i + 1;
        if i % 2 == 1 {
            continue;
        }
        s = s + i;
    }
    return s;
}
