# expect: 33
# 结构体 + 数组 + 递归 + 全局量 综合
struct Node {
    val: i64;
    cnt: i64;
}

var total: i64 = 0;
var tbl: [8] i64 = 0;

fn fib(n: i64) -> i64 {
    if n < 2 {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i64 {
    let nd: Node;
    nd.val = fib(7);
    nd.cnt = 0;
    let i: i64 = 0;
    while i < 5 {
        tbl[i] = i * 2;
        nd.cnt = nd.cnt + tbl[i];
        i = i + 1;
    }
    total = nd.val + nd.cnt;
    return total;
}
