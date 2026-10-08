# expect: 12
# 嵌套循环：break 只跳出内层
fn main() -> i64 {
    let total: i64 = 0;
    let i: i64 = 1;
    while i <= 3 {
        let j: i64 = 1;
        while j <= 10 {
            if j > i {
                break;
            }
            total = total + 1;
            j = j + 1;
        }
        i = i + 1;
    }
    return total * 2;
}
