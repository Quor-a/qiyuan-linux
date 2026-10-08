# expect: 0
# 标准库第一轮：字符串与内存
import "io.mo";
import "str.mo";
import "mem.mo";

var buf: [32] i64 = 0;
var buf2: [32] i64 = 0;

fn main() -> i64 {
    print_i64(strlen("hello"));
    print_nl();
    if streq("abc", "abc") == 1 {
        print("streq ok\n");
    }
    if streq("abc", "abd") == 0 {
        print("streq ne ok\n");
    }
    strcpy(&buf, "copy me");
    print(&buf);
    print_nl();
    memset(&buf2, 65, 3);
    store8(&buf2 + 3, 0);
    print(&buf2);
    print_nl();
    memcpy(&buf, &buf2, 4);
    print(&buf);
    print_nl();
    heap_init();
    let p: i64 = alloc(64);
    strcpy(p, "heap");
    print(p);
    print_nl();
    return 0;
}
