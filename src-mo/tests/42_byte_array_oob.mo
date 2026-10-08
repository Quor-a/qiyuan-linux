# expect: 1
# byte 数组的变量下标越界同样在运行时被拦住
fn main() -> i64 {
    let b: [4] byte = 0;
    let i: i64 = 9;
    b[i] = 1;
    return 0;
}
