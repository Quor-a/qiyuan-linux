# expect: 55
# 注：进程退出码只取低 8 位，故用 fib(10)=55 验证
fn fib(n: i64) -> i64 {
    if n < 2 {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}
fn main() -> i64 {
    return fib(10);
}
