# expect: 14
# 边界内访问不受影响：0+1+4+9=14
fn main() -> i64 {
    let a: [4] i64 = 0;
    let i: i64 = 0;
    while i < 4 {
        a[i] = i * i;
        i = i + 1;
    }
    return a[0] + a[1] + a[2] + a[3];
}
