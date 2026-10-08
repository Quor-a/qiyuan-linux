# expect: 55
var acc: i64 = 0;
fn main() -> i64 {
    let i: i64 = 1;
    while i <= 10 {
        acc = acc + i;
        i = i + 1;
    }
    return acc;
}
