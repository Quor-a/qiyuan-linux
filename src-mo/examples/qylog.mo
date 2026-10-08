# qylog —— qypkg 包仓库查询工具（用墨语言写的实战工具 #2）
#
# 用途：列出包仓库目录，统计文件/目录数与大小。
#   ./qylog <目录路径>
#
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var dname: [64000] byte = 0;
var dtype: [250] byte = 0;
var pathbuf: [4096] byte = 0;

fn main() -> i64 {
    print("qylog —— 墨语言写的 qypkg 仓库查询\n\n");
    if argc() < 2 {
        print("用法: qylog <目录>\n");
        return 1;
    }
    let path: i64 = argv(1);
    print("目录: ");
    print(path);
    print("\n\n");
    let n: i64 = dir_list(path, &dname, &dtype, 256, 249);
    if n < 0 {
        print("错误：打不开目录\n");
        return 1;
    }
    print_i64(n);
    print(" 个条目:\n");
    let i: i64 = 0;
    let nfile: i64 = 0;
    let ndir: i64 = 0;
    while i < n {
        strcpy(&pathbuf, path);
        strcat(&pathbuf, "/");
        strcat(&pathbuf, &dname + i * 256);
        if dtype[i] == 4 {
            ndir = ndir + 1;
            print("  [目录] ");
            print(&dname + i * 256);
        } else {
            nfile = nfile + 1;
            print("  [文件] ");
            print(&dname + i * 256);
            print("  ");
            print_i64(stat_size(&pathbuf));
            print(" 字节");
        }
        print("\n");
        i = i + 1;
    }
    print("\n合计: ");
    print_i64(nfile);
    print(" 文件, ");
    print_i64(ndir);
    print(" 目录\n");
    return 0;
}
