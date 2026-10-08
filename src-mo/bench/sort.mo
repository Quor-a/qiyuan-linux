# 基准：冒泡排序 3000 元素。考察嵌套循环 + 数组交换
var a: [3000] i64 = 0;
fn main() -> i64 {
    let i: i64 = 0;
    while i < 3000 {
        a[i] = (3000 - i) * 7 & 1023;
        i = i + 1;
    }
    let n: i64 = 3000;
    let x: i64 = 0;
    while x < n {
        let y: i64 = 0;
        while y < n - 1 - x {
            if a[y] > a[y + 1] {
                let t: i64 = a[y];
                a[y] = a[y + 1];
                a[y + 1] = t;
            }
            y = y + 1;
        }
        x = x + 1;
    }
    return a[0] & 255;
}
