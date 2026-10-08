# 极简 bump 分配器：只增不减，按 16 字节对齐
# 用法：先 heap_init()，之后 alloc(n) 返回可用地址
#
# 注意：alloc 不会返回 0 表示失败 —— 它直接把 brk 往上推。
# 内存真正耗尽时是 brk 失败，而那没有被检查。
# 也就是说「分配成功」不代表后面真的有可写内存。
# 想要失败信号得自己加容量上限，这是当前实现的一个真实局限。

var hb: i64 = 0;
var hp: i64 = 0;

fn heap_init() -> i64 {
    hb = syscall(12, 0, 0, 0, 0, 0, 0);
    hp = hb;
    return hb;
}

fn alloc(n: i64) -> i64 {
    let p: i64 = hp;
    hp = hp + ((n + 15) & -16);
    syscall(12, hp + 4096, 0, 0, 0, 0, 0);
    return p;
}

fn alloc8(n: i64) -> i64 {
    return alloc(n * 8);
}

fn heap_used() -> i64 {
    return hp - hb;
}

fn heap_reset() -> i64 {
    hp = hb;
    return hp;
}
