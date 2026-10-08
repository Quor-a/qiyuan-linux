# expect: 3
fn cls(n: i64) -> i64 {
    if n > 0 {
        if n > 10 {
            return 1;
        } else {
            return 2;
        }
    }
    return 3;
}
fn main() -> i64 {
    return cls(0);
}
