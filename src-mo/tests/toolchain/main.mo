# expect: 0
# 工具链测试：命令行参数 + 断言框架 + bump 分配器
import "io.mo";
import "assert.mo";
import "mem.mo";

var ncheck: i64 = 0;

fn main() -> i64 {
    # 命令行参数：run.sh 只传输入文件，argc 应为 1
    print_i64(argc());
    print_nl();
    if argc() >= 1 {
        print(argv(0));
        print_nl();
    }
    # 断言框架
    assert_eq("add", 1 + 1, 2);
    assert_eq("dummy", strlen_dummy(), 5);
    ncheck = 2;
    print_i64(ncheck);
    print_nl();
    # bump 分配器：连续分配，地址递增，16 字节对齐
    heap_init();
    let a: i64 = alloc(1);
    let b: i64 = alloc(1);
    if b > a {
        print("alloc advances\n");
    }
    if (a & 15) == 0 {
        print("alloc aligned\n");
    }
    heap_reset();
    test_done();
    return 0;
}

fn strlen_dummy() -> i64 {
    return 5;
}
