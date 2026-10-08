fn b_entry(n: i64) -> i64 {
    return b_local(n) + b_local(n + 1);
}

fn b_local(n: i64) -> i64 {
    return n * 4;
}
