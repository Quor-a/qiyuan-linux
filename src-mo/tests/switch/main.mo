# expect: 0
# switch：case 匹配/贯穿/else/break/负值
import "io.mo";
fn cls(n: i64) -> i64 {
    switch n {
        0 { return 10; }
        1 { return 11; }
        2 { return 12; }
        else { return -1; }
    }
    return -99;
}
fn main() -> i64 {
    print_i64(cls(0)); print(" ");
    print_i64(cls(1)); print(" ");
    print_i64(cls(2)); print(" ");
    print_i64(cls(9)); print("  expect 10 11 12 -1\n");
    # 负 case 值
    let x: i64 = -2;
    switch x {
        1 { print("pos\n"); }
        -2 { print("neg\n"); }
        else { print("none\n"); }
    }
    # break 只跳 switch 不跳外层 while
    let i: i64 = 0;
    while i < 2 {
        switch i {
            0 { print("A\n"); break; }
            else { print("B\n"); }
        }
        print("L\n");
        i = i + 1;
    }
    return 0;
}
