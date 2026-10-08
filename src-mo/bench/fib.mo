# 基准：递归 fib(32)。函数调用 + 栈帧 + 递归深度
fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}
fn main() -> i64 {
    return fib(32);
}
