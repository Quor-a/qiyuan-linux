# expect-error: index out of bounds: constant index >= array length
# 常量下标越界在编译期就能发现，不必等到运行时
fn main() -> i64 {
    let a: [4] i64 = 0;
    return a[9];
}
