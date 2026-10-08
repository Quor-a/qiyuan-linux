# expect: 0
# JSON 解析与 tar/gzip 归档
import "io.mo";
import "str.mo";
import "fs.mo";
import "json.mo";
import "archive.mo";

var v: [128] byte = 0;
var files: [4] i64 = 0;
var rbuf: [256] byte = 0;

fn main() -> i64 {
    # --- JSON ---
    let j: i64 = "{\"name\":\"mo\",\"version\":13,\"neg\":-7,\"fast\":true,\"off\":false,\"dep\":null}";
    if json_str(j, "name", &v) != 1 { return 1; }
    if streq(&v, "mo") == 0 { return 2; }
    if json_int(j, "version") != 13 { return 3; }
    if json_int(j, "neg") != -7 { return 4; }
    if json_true(j, "fast") != 1 { return 5; }
    if json_true(j, "off") != 0 { return 6; }
    # 不存在的键
    if json_str(j, "nope", &v) != 0 { return 7; }

    # --- tar 打包 + 列目录 + 解包 ---
    let w: i64 = fopen("p1.txt", 577, 420);
    fwrite(w, "first file\n", 11); fclose(w);
    let w2: i64 = fopen("p2.txt", 577, 420);
    fwrite(w2, "second\n", 7); fclose(w2);
    files[0] = "p1.txt";
    files[1] = "p2.txt";
    if tar_pack("t.tar", &files, 2) != 0 { return 8; }
    if tar_list("t.tar") != 2 { return 9; }

    # --- gzip 往返 ---
    if gzip_file("p1.txt", "p1.gz") != 0 { return 10; }
    if gunzip_file("p1.gz", "p1.back") != 0 { return 11; }
    let a: [64] byte = 0;
    let b: [64] byte = 0;
    read_file("p1.txt", &a, 63);
    read_file("p1.back", &b, 63);
    if streq(&a, &b) == 0 { return 12; }

    print("json + archive ok\n");
    return 0;
}
