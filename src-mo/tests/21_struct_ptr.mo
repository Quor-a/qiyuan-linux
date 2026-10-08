# expect: 9
# 结构体经 & 取地址传入函数，按指针读写字段
struct Box {
    v: i64;
}

fn bump(b: i64) -> i64 {
    store64(b, load64(b) + 1);
    return load64(b);
}

fn main() -> i64 {
    let x: Box;
    x.v = 8;
    return bump(&x);
}
