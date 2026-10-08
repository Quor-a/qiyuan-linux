# expect: 55
# 数组与递归配合：全局数组做记忆化的 fib
var memo: [32] i64 = 0;

fn fib(n: i64) -> i64 {
    if n < 2 {
        return n;
    }
    if memo[n] != 0 {
        return memo[n];
    }
    memo[n] = fib(n - 1) + fib(n - 2);
    return memo[n];
}

fn main() -> i64 {
    return fib(10);
}
