# expect: 30
# break：累加 1..10，遇到 >5 就跳出
fn main() -> i64 {
    let s: i64 = 0;
    let i: i64 = 1;
    while i <= 10 {
        if i > 5 {
            break;
        }
        s = s + i;
        i = i + 1;
    }
    return s * 2;
}
