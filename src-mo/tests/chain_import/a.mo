import "b.mo";

fn a_entry(n: i64) -> i64 {
    return b_entry(n) + a_local(n);
}

fn a_local(n: i64) -> i64 {
    return n * 2;
}
