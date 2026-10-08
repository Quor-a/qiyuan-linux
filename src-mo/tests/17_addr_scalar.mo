# expect: 9
# 对标量取地址后通过指针读写
fn main() -> i64 {
    let x: i64 = 7;
    let p: i64 = &x;
    store64(p, load64(p) + 2);
    return x;
}
