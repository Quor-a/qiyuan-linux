# expect: 0
# const 常量：i64 与 f64
import "io.mo";
const MAX: i64 = 100;
const PI: f64 = 3.14159265358979;
fn main() -> i64 {
    print_i64(MAX); print("\n");
    print_f64(PI); print("\n");
    return 0;
}
