# expect: 14
# 数组元素作为函数实参、下标表达式作为形参来源
var g: [4] i64 = 0;

fn dbl(x: i64) -> i64 {
    return x * 2;
}

fn main() -> i64 {
    g[0] = 3;
    g[1] = 4;
    return dbl(g[0]) + dbl(g[1]);
}
