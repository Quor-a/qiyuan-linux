# expect-error: cannot assign to an array
# 数组整体不能做复合赋值
fn main() -> i64 {
    let a: [4] i64 = 0;
    a += 1;
    return 0;
}
