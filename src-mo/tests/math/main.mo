# expect: 0
# math 库：sqrt/exp/log/pow/sin/cos/tan/atan（输出 15 行校验值）
import "math.mo";
import "io.mo";

fn main() -> i64 {
    print_f64(qsqrt(2.0)); print("\n");       # 1.414214
    print_f64(qexp(1.0)); print("\n");        # 2.718282
    print_f64(qlog(10.0)); print("\n");       # 2.302585
    print_f64(qpow(2.0, 10.0)); print("\n");  # 1024
    print_f64(qsin(1.0)); print("\n");        # 0.841471
    print_f64(qcos(1.0)); print("\n");        # 0.540302
    print_f64(qtan(0.7853981633974483)); print("\n");  # 1
    print_f64(qat(1.0)); print("\n");         # 0.785398
    print_f64(qsqrt(16.0)); print("\n");      # 4
    print_f64(qat(1.0) * 4.0); print("\n");   # 3.141593
    print_f64(qpow(9.0, 0.5)); print("\n");   # 3
    print_f64(qlog(2.718281828459045)); print("\n");  # 1
    print_f64(qexp(6.93147180559945)); print("\n");   # 1024
    print_f64(qsin(3.14159265358979 / 6.0)); print("\n");  # 0.5
    print_f64(qcos(3.14159265358979)); print("\n");   # -1
    return 0;
}
