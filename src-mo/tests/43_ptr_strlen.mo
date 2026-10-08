# expect: 5
# ptr（指向字节的指针）：字符串形参可以直接用下标，不用 load8 手算
fn strlen(s: ptr) -> i64 {
    let i: i64 = 0;
    while s[i] != 0 {
        i = i + 1;
    }
    return i;
}

fn main() -> i64 {
    return strlen("hello");
}
