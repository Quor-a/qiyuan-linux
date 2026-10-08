# expect: 0
# 动态数组：扩容、读写、越界、pop、clear
import "io.mo";
import "str.mo";
import "mem.mo";
import "vec.mo";

fn main() -> i64 {
    heap_init();
    let v: i64 = vec_new();

    # 基础：连续 push 1000 个，必然触发多次扩容
    let i: i64 = 0;
    while i < 1000 {
        vec_push(v, i * 3);
        i = i + 1;
    }
    if vec_len(v) != 1000 { return 1; }
    if vec_cap(v) < 1000 { return 2; }

    # 值必须保持正确（扩容后仍在）
    i = 0;
    while i < 1000 {
        if vec_get(v, i) != i * 3 { return 3; }
        i = i + 1;
    }

    # set 覆盖
    vec_set(v, 5, 999);
    if vec_get(v, 5) != 999 { return 4; }

    # 越界读写都不该崩，get 返回 0，set 无效果
    if vec_get(v, 1000) != 0 { return 5; }
    if vec_get(v, 0 - 1) != 0 { return 6; }
    vec_set(v, 9999, 1);
    if vec_len(v) != 1000 { return 7; }

    # pop 取回最后一个
    if vec_pop(v) != 999 * 3 { return 8; }
    if vec_len(v) != 999 { return 9; }

    # clear 后长度归零，但可以继续用
    vec_clear(v);
    if vec_len(v) != 0 { return 10; }
    vec_push(v, 7);
    if vec_get(v, 0) != 7 { return 11; }

    # 存字符串指针：这是真实用法
    let s: i64 = vec_new();
    vec_push(s, "banana");
    vec_push(s, "apple");
    if streq(vec_get(s, 0), "banana") == 0 { return 12; }
    if streq(vec_get(s, 1), "apple") == 0 { return 13; }

    print("vec ok, heap used = ");
    print_i64(heap_used());
    print_nl();
    return 0;
}
