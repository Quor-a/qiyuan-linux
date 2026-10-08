# expect: 0
# 字符串键映射：插入、更新、扩容、不存在、计数
import "io.mo";
import "str.mo";
import "mem.mo";
import "map.mo";

fn main() -> i64 {
    heap_init();
    let m: i64 = map_new();

    # 基础读写
    if map_put(m, "apple", 5) != 1 { return 1; }
    if map_get(m, "apple") != 5 { return 2; }
    if map_len(m) != 1 { return 3; }

    # 更新：返回 0 表示是更新而非新建，长度不变
    if map_put(m, "apple", 9) != 0 { return 4; }
    if map_get(m, "apple") != 9 { return 5; }
    if map_len(m) != 1 { return 6; }

    # 不存在的键：get 返回 0，has 返回 0
    if map_has(m, "banana") != 0 { return 7; }
    if map_get(m, "banana") != 0 { return 8; }

    # 插入 2000 个键，必然触发多次 rehash
    let i: i64 = 0;
    let tmp: [24] byte = 0;
    while i < 2000 {
        utoa(i, &tmp, 10);
        map_put(m, &tmp, i * 7);
        i = i + 1;
    }
    if map_len(m) != 2001 { return 9; }

    # rehash 之后老键仍然找得到（这是 rehash 最容易写错的地方）
    if map_get(m, "apple") != 9 { return 10; }
    i = 0;
    while i < 2000 {
        utoa(i, &tmp, 10);
        if map_get(m, &tmp) != i * 7 { return 11; }
        i = i + 1;
    }

    # 长键与相似键不能互相覆盖（哈希必须真的按内容算）
    map_put(m, "a", 1);
    map_put(m, "ab", 2);
    map_put(m, "abc", 3);
    if map_get(m, "a") != 1 { return 12; }
    if map_get(m, "ab") != 2 { return 13; }
    if map_get(m, "abc") != 3 { return 14; }

    # 键被拷进堆里：复用同一个缓冲区不会串味
    let k: i64 = alloc(32);
    strcpy(k, "k1");
    map_put(m, k, 100);
    strcpy(k, "k2");
    map_put(m, k, 200);
    if map_get(m, "k1") != 100 { return 15; }
    if map_get(m, "k2") != 200 { return 16; }

    # map_inc：不存在的键从 1 开始，存在则累加
    let c: i64 = map_new();
    if map_inc(c, "x") != 1 { return 17; }
    if map_inc(c, "x") != 2 { return 18; }
    if map_inc(c, "x") != 3 { return 19; }
    if map_len(c) != 1 { return 20; }

    print("map ok, len = ");
    print_i64(map_len(m));
    print_nl();
    return 0;
}
