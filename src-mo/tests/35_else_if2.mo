# expect: 3
# 没有 else 收尾的 else if 链
fn cls(n: i64) -> i64 {
    let r: i64 = 0;
    if n == 1 {
        r = 1;
    } else if n == 2 {
        r = 2;
    } else if n == 3 {
        r = 3;
    }
    return r;
}

fn main() -> i64 {
    return cls(3);
}
