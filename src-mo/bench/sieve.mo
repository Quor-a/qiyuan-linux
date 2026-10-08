# 基准：埃拉托斯特尼筛法，10 万以内素数计数
var f: [100000] byte = 0;
fn main() -> i64 {
    let n: i64 = 100000;
    let i: i64 = 2;
    while i < n {
        if f[i] == 0 {
            let j: i64 = i * i;
            while j < n {
                f[j] = 1;
                j = j + i;
            }
        }
        i = i + 1;
    }
    let c: i64 = 0;
    i = 2;
    while i < n {
        if f[i] == 0 { c = c + 1; }
        i = i + 1;
    }
    return c & 255;
}
