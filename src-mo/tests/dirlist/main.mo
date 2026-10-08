# expect: 0
# dir_list 批量列目录（启元新增）：条目数与类型
import "dir.mo";
import "io.mo";
var n_buf: [1024] byte = 0;
var t_buf: [4] byte = 0;
fn main() -> i64 {
    let n: i64 = dir_list("d", &n_buf, &t_buf, 256, 4);
    if n != 2 { return 1; }
    if load8(&t_buf) != 8 { return 2; }
    if load8(&t_buf + 1) != 8 { return 3; }
    print("dir_list ok");
    return 0;
}
