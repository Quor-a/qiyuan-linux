# expect: 5
fn strlen(s: i64) -> i64 {
    let n: i64 = 0;
    while load8(s + n) != 0 {
        n = n + 1;
    }
    return n;
}
fn main() -> i64 {
    return strlen("hello");
}
