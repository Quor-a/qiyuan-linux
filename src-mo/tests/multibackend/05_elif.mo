# expect: 166
fn cls(n: i64) -> i64 {
    if n < 10 { return 1; }
    else if n < 20 { return 2; }
    else if n < 30 { return 3; }
    else { return 9; }
    return 0;
}
fn main() -> i64 {
    return cls(5) * 1000 + cls(15) * 100 + cls(25) * 10 + cls(99) - 1329;
}
