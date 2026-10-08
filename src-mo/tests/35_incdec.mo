# expect: 0
# 自增自减 ++ / --：覆盖标量、全局、数组下标、结构体字段
# 复合赋值：覆盖同一批左值形态 × 五种运算符
struct S { v: i64; }
var g: i64 = 100;

fn main() -> i64 {
    # --- 标量 ---
    let n: i64 = 100;
    n++;
    if n != 101 { return 1; }
    n--;
    n--;
    if n != 99 { return 2; }

    # --- 全局 ---
    g++;
    if g != 101 { return 3; }
    g--;
    if g != 100 { return 4; }

    # --- 数组下标 ---
    let a: [4] i64 = 0;
    a[0] = 100;
    a[0]++;
    if a[0] != 101 { return 5; }
    a[0]--;
    a[0]--;
    if a[0] != 99 { return 6; }

    # --- 结构体字段 ---
    let s: S;
    s.v = 100;
    s.v++;
    if s.v != 101 { return 7; }
    s.v--;
    s.v--;
    if s.v != 99 { return 8; }

    # --- 复合赋值：同样的四类左值 ---
    n = 100;
    n += 7;  if n != 107 { return 9; }
    n -= 5;  if n != 102 { return 10; }
    n *= 2;  if n != 204 { return 11; }
    n /= 4;  if n != 51  { return 12; }
    n %= 10; if n != 1   { return 13; }

    a[0] = 100;
    a[0] += 7; if a[0] != 107 { return 14; }
    a[0] -= 5; if a[0] != 102 { return 15; }
    a[0] /= 2; if a[0] != 51  { return 16; }

    s.v = 100;
    s.v += 7; if s.v != 107 { return 17; }
    s.v -= 5; if s.v != 102 { return 18; }
    s.v *= 2; if s.v != 204 { return 19; }
    s.v /= 4; if s.v != 51  { return 20; }
    s.v %= 10; if s.v != 1  { return 21; }

    g = 100;
    g += 7; if g != 107 { return 22; }

    # --- 循环里用自增（最典型的场景）---
    let i: i64 = 0;
    let sum: i64 = 0;
    while i < 10 {
        sum += i;
        i++;
    }
    if sum != 45 { return 23; }
    if i != 10 { return 24; }

    return 0;
}
