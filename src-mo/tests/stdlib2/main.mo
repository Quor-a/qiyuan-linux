# expect: 0
# 标准库第二轮：转换与查找
import "io.mo";
import "str.mo";

fn main() -> i64 {
    print_i64(atoi("12345"));
    print_nl();
    print_i64(atoi("-789"));
    print_nl();
    print_i64(atoi("12abc"));
    print_nl();
    print_hex(255);
    print_nl();
    print_i64(strchr("hello", 108));
    print_nl();
    print_i64(strlen("abc"));
    print_nl();
    # strcmp：负数 / 0 / 正数
    print_i64(strcmp("abc", "abd") < 0);
    print_i64(strcmp("abc", "abc") == 0);
    print_i64(strcmp("abd", "abc") > 0);
    print_nl();
    return 0;
}
