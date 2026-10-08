# 库文件：调用主文件里定义的 main_helper（跨文件前向引用）
fn lib_entry(n: i64) -> i64 {
    return main_helper(n) + lib_local(n);
}

fn lib_local(n: i64) -> i64 {
    return n + 2;
}
