# expect: 48
fn add2(a: i64, b: i64) -> i64 {
    return a + b;
}
fn main() -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 4 {
        let j: i64 = 0;
        while j < 4 {
            s = s + add2(i, j);
            j = j + 1;
        }
        i = i + 1;
    }
    # i,j 各 0..3，sum(i+j)*4 = (0+1+2+3)*4*4 = 96
    return s & 255;
}
