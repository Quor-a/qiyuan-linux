# qydu —— 磁盘用量分析器（墨语言实战工具 #4）
#
# 递归扫描目录，统计每个子目录的文件数与总字节，按大小排序输出。
# 实战压测点：递归函数、dir_list 批量接口、stat_size/is_dir、
# 数组寻址运算、多返回值合作、深度优先遍历。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

# 结果表：最多 256 个目录条目
var r_paths: [16384] byte = 0;     # 256 * 64 路径
var r_sizes: [2048] byte = 0;      # 256 * 8 低字节即可（此处用 i64 拆存会复杂，改用双数组）
var r_files: [256] byte = 0;       # 文件计数（byte 够用演示，真实需 i64）
var r_count: i64 = 0;

var pathbuf: [4096] byte = 0;
# 递归可重入：每个深度一层独立缓冲（depth 最大 12）
var sub_names0: [64000] byte = 0;
var sub_types0: [250] byte = 0;
var sub_names1: [64000] byte = 0;
var sub_types1: [250] byte = 0;
var sub_names2: [64000] byte = 0;
var sub_types2: [250] byte = 0;
var sub_names3: [64000] byte = 0;
var sub_types3: [250] byte = 0;
var sub_names4: [64000] byte = 0;
var sub_types4: [250] byte = 0;
var sub_names5: [64000] byte = 0;
var sub_types5: [250] byte = 0;
var sub_names6: [64000] byte = 0;
var sub_types6: [250] byte = 0;
var sub_names7: [64000] byte = 0;
var sub_types7: [250] byte = 0;
var rec_path0: [1024] byte = 0;
var rec_path1: [1024] byte = 0;
var rec_path2: [1024] byte = 0;
var rec_path3: [1024] byte = 0;
var rec_path4: [1024] byte = 0;
var rec_path5: [1024] byte = 0;
var rec_path6: [1024] byte = 0;
var rec_path7: [1024] byte = 0;
var path_at_idx: i64 = 0;
var tmp_name: [64] byte = 0;

fn rec_path_at(depth: i64) -> i64 {
    if depth == 0 { return &rec_path0; }
    if depth == 1 { return &rec_path1; }
    if depth == 2 { return &rec_path2; }
    if depth == 3 { return &rec_path3; }
    if depth == 4 { return &rec_path4; }
    if depth == 5 { return &rec_path5; }
    if depth == 6 { return &rec_path6; }
    return &rec_path7;
}

fn names_at(depth: i64) -> i64 {
    if depth == 0 { return &sub_names0; }
    if depth == 1 { return &sub_names1; }
    if depth == 2 { return &sub_names2; }
    if depth == 3 { return &sub_names3; }
    if depth == 4 { return &sub_names4; }
    if depth == 5 { return &sub_names5; }
    if depth == 6 { return &sub_names6; }
    return &sub_names7;
}

fn types_at(depth: i64) -> i64 {
    if depth == 0 { return &sub_types0; }
    if depth == 1 { return &sub_types1; }
    if depth == 2 { return &sub_types2; }
    if depth == 3 { return &sub_types3; }
    if depth == 4 { return &sub_types4; }
    if depth == 5 { return &sub_types5; }
    if depth == 6 { return &sub_types6; }
    return &sub_types7;
}

# 把 i64 尺寸存进 8 字节槽
fn put64(base: i64, slot: i64, v: i64) -> i64 {
    let j: i64 = 0;
    while j < 8 {
        store8(base + slot * 8 + j, (v >> (j * 8)) & 255);
        j = j + 1;
    }
    return 0;
}

fn get64(base: i64, slot: i64) -> i64 {
    let v: i64 = 0;
    let j: i64 = 7;
    while j >= 0 {
        v = v * 256 + load8(base + slot * 8 + j);
        j = j - 1;
    }
    return v;
}

# 递归扫描：累计本目录直接文件大小；子目录递归后再记一条
fn scan(path: i64, depth: i64) -> i64 {
    if depth > 7 { return 0; }
    let nm_buf: i64 = names_at(depth);
    let ty_buf: i64 = types_at(depth);
    let rp: i64 = rec_path_at(depth);
    let n: i64 = dir_list(path, nm_buf, ty_buf, 256, 249);
    if n < 0 { return 0; }
    let total: i64 = 0;
    let files: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let nm: i64 = nm_buf + i * 256;
        if streq(nm, ".") != 1 && streq(nm, "..") != 1 {
            strcpy(rp, path);
            strcat(rp, "/");
            strcat(rp, nm);
            let t: i64 = load8(ty_buf + i);
            if t == 4 {
                # d_type 4 = 目录，递归
                total = total + scan(rp, depth + 1);
            } else {
                let sz: i64 = stat_size(rp);
                if sz > 0 { total = total + sz; }
                files = files + 1;
            }
        }
        i = i + 1;
    }
    # 记录本目录
    if r_count < 256 {
        strcpy(&r_paths + r_count * 64, path);
        put64(&r_sizes, r_count, total);
        store8(&r_files + r_count, files);
        r_count = r_count + 1;
    }
    return total;
}

fn fmt_size(v: i64) -> i64 {
    # 打印人可读大小
    if v >= 1073741824 {
        print_i64(v / 1073741824);
        print(".x GiB");
    } else if v >= 1048576 {
        print_i64(v / 1048576);
        print(".x MiB");
    } else if v >= 1024 {
        print_i64(v / 1024);
        print(".x KiB");
    } else {
        print_i64(v);
        print(" B");
    }
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("用法: qydu <目录>\n");
        return 1;
    }
    let target: i64 = argv(1);
    r_count = 0;
    let grand: i64 = scan(target, 0);
    # 按大小冒泡排序（降序）
    let i: i64 = 0;
    while i < r_count {
        let j: i64 = 0;
        while j < r_count - 1 - i {
            if get64(&r_sizes, j) < get64(&r_sizes, j + 1) {
                # 交换 sizes
                let a: i64 = get64(&r_sizes, j);
                put64(&r_sizes, j, get64(&r_sizes, j + 1));
                put64(&r_sizes, j + 1, a);
                # 交换 paths（64 字节）
                memcpy(&tmp_name, &r_paths + j * 64, 64);
                memcpy(&r_paths + j * 64, &r_paths + (j + 1) * 64, 64);
                memcpy(&r_paths + (j + 1) * 64, &tmp_name, 64);
                # 交换 files
                let f: i64 = r_files[j];
                r_files[j] = r_files[j + 1];
                r_files[j + 1] = f;
            }
            j = j + 1;
        }
        i = i + 1;
    }
    # 输出
    print("目录\t\t大小\t文件数\n");
    let k: i64 = 0;
    while k < r_count {
        print(&r_paths + k * 64);
        print("  ");
        fmt_size(get64(&r_sizes, k));
        print("  ");
        print_i64(load8(&r_files + k));
        print("\n");
        k = k + 1;
    }
    print("合计 ");
    fmt_size(grand);
    print(" / ");
    print_i64(r_count);
    print(" 个目录\n");
    return 0;
}
