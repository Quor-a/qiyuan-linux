# expect: 36
# 主文件与库文件互相调用：main 调 lib，lib 回调 main 里的函数
import "lib.mo";

var total: i64 = 0;

fn main_helper(n: i64) -> i64 {
    return n * 3;
}

fn main() -> i64 {
    total = lib_entry(4);
    return total + main_helper(6);
}
