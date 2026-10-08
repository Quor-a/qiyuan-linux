# expect: 54
# 链式 import：main -> a -> b，三方函数互调
import "a.mo";

fn main() -> i64 {
    return a_entry(5);
}
