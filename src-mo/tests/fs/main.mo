# expect: 11
# 文件 IO 测试：写入临时文件再读回，验证读写双向
# 不依赖外部数据文件（测试脚本只拷 .mo），自己造数据
import "fs.mo";
import "io.mo";
import "str.mo";

var buf: [64] i64 = 0;

fn main() -> i64 {
    # 写：O_CREAT|O_WRONLY|O_TRUNC = 577，模式 0644 = 420
    let fd: i64 = fopen("t.txt", 577, 420);
    if fd < 0 {
        print("open for write failed\n");
        return 1;
    }
    fwrite(fd, "hello, file!", 12);
    fclose(fd);

    # 读回
    let n: i64 = read_file("t.txt", &buf, 512);
    if n < 0 {
        print("read failed\n");
        return 2;
    }
    if n != 12 {
        print_i64(n);
        print(" != 12\n");
        return 3;
    }
    fputs(&buf);
    print_nl();
    if streq(&buf, "hello, file!") == 0 {
        print("content mismatch\n");
        return 4;
    }
    return 11;
}
