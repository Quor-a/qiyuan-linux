# qycheck —— 启元 qyp 包元数据校验器（用墨语言写的实战工具）
#
# 用途：读一个包的元数据 JSON，校验必备字段齐全，打印摘要。
#       实战检验墨语言做包管理工具的能力（JSON/文件IO/字符串/逻辑）。
#
#   ./qycheck <json文件>
#
import "io.mo";
import "fs.mo";
import "str.mo";
import "json.mo";

var buf: [65536] byte = 0;
var val: [4096] byte = 0;

var n_ok: i64 = 0;
var n_missing: i64 = 0;

# 必备字段一个一个查；缺失计数
fn require(key: ptr) -> i64 {
    if json_str(&buf, key, &val) == 1 {
        print("  ✓ ");
        print(key);
        print(" = ");
        print(&val);
        print("\n");
        n_ok = n_ok + 1;
        return 0;
    }
    # 数字字段试一下
    let iv: i64 = json_int(&buf, key);
    let p: i64 = find_key(&buf, key, 0);
    if p >= 0 {
        print("  ✓ ");
        print(key);
        print(" = ");
        print_i64(iv);
        print("\n");
        n_ok = n_ok + 1;
        return 0;
    }
    print("  ✗ 缺失: ");
    print(key);
    print("\n");
    n_missing = n_missing + 1;
    return -1;
}

fn main() -> i64 {
    print("qycheck —— 墨语言写的 qyp 元数据校验器\n\n");
    let n: i64 = read_file("meta.json", &buf, 65535);
    if n < 0 {
        print("错误：读不到 meta.json\n");
        return 1;
    }
    store8(&buf + n, 0);
    print("读取 meta.json ");
    print_i64(n);
    print(" 字节\n\n[必备字段]\n");
    require("name");
    require("version");
    require("license");
    require("summary");
    print("\n[结果] ");
    print_i64(n_ok);
    print(" 项通过, ");
    print_i64(n_missing);
    print(" 项缺失\n");
    if n_missing > 0 {
        print("校验失败\n");
        return 1;
    }
    print("校验通过（此工具由墨语言编译，原生 ELF，零 libc 依赖）\n");
    return 0;
}
