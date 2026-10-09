# qyfind —— 文件查找工具（墨语言实战工具 #17）
#
# 用法:
#   qyfind <目录> -name <模式>     按文件名通配符查找（* 与 ?）
#   qyfind <目录> -type f|d        按类型过滤（f=普通文件 d=目录）
#   qyfind <目录> -size +N         按大小过滤（大于 N 字节）
#
# 退出码：找到 0，没找到 1，用法错 2。
# 实战压测点：递归路径按深度分槽（不可重入陷阱）、通配符匹配、
# 与 find 命令对账。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var dir_names: [64000] byte = 0;
var dir_types: [250] byte = 0;
var paths: [7168] byte = 0;       # 7 槽 × 1024
var pat: [256] byte = 0;
var path_now: [1024] byte = 0;
var cur_path: [1024] byte = 0;    # 正在比较的完整路径（匹配用文件名，输出用全路径）

var want_type: i64 = 0;           # 0=不过滤 1=f 2=d
var min_size: i64 = -1;
var found: i64 = 0;

fn itoa10(v: i64, dst: i64) -> i64 {
    let t: [20] byte = 0;
    let d: i64 = 0;
    let x: i64 = v;
    if x == 0 { store8(&t, 48); d = 1; }
    while x > 0 {
        store8(&t + d, 48 + (x % 10));
        d = d + 1;
        x = x / 10;
    }
    let i: i64 = 0;
    while i < d {
        store8(dst + i, load8(&t + d - 1 - i));
        i = i + 1;
    }
    store8(dst + d, 0);
    return d;
}

# 通配符匹配：* 任意串、? 单字符，其余逐字符
fn wildmatch(s: i64, p: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let star: i64 = -1;
    let ss: i64 = 0;
    while load8(s + i) != 0 {
        let pc: i64 = load8(p + j);
        if pc == 63 {
            i = i + 1; j = j + 1;
        } else {
            if pc == 42 {
                star = j;
                ss = i;
                j = j + 1;
            } else {
                if pc == load8(s + i) {
                    i = i + 1; j = j + 1;
                } else {
                    if star >= 0 {
                        j = star + 1;
                        ss = ss + 1;
                        i = ss;
                    } else {
                        return 0;
                    }
                }
            }
        }
    }
    while load8(p + j) == 42 { j = j + 1; }
    if load8(p + j) == 0 { return 1; }
    return 0;
}

# 取路径最后一段文件名
fn basename(p: i64, dst: i64) -> i64 {
    let n: i64 = strlen(p);
    let k: i64 = n - 1;
    while k >= 0 {
        if load8(p + k) == 47 { break; }
        k = k - 1;
    }
    strcpy(dst, p + k + 1);
    return 0;
}

fn hit(name: i64, isdir: i64, fullpath: i64) -> i64 {
    if want_type == 1 && isdir == 1 { return 0; }
    if want_type == 2 && isdir == 0 { return 0; }
    if min_size >= 0 {
        if isdir == 1 { return 0; }   # -size 只对普通文件有意义
        if stat_size(fullpath) <= min_size { return 0; }
    }
    if strlen(&pat) > 0 {
        if wildmatch(name, &pat) != 1 { return 0; }
    }
    print(fullpath); print("\n");
    found = found + 1;
    return 0;
}

fn find_dir(depth: i64) -> i64 {
    if depth > 6 { return 0; }
    let here: i64 = &paths + depth * 1024;
    let n: i64 = dir_list(here, &dir_names, &dir_types, 256, 249);
    if n < 0 { return 0; }
    let child: i64 = &paths + (depth + 1) * 1024;
    let i: i64 = 0;
    while i < n {
        let nm: i64 = &dir_names + i * 256;
        if streq(nm, ".") != 1 && streq(nm, "..") != 1 {
            strcpy(child, here);
            strcat(child, "/");
            strcat(child, nm);
            let isd: i64 = 0;
            if load8(&dir_types + i) == 4 { isd = 1; }
            strcpy(&cur_path, child);
            hit(nm, isd, &cur_path);
            if isd == 1 { find_dir(depth + 1); }
        }
        i = i + 1;
    }
    return 0;
}

fn main() -> i64 {
    if argc() < 3 {
        print("用法: qyfind <目录> [-name 通配] [-type f|d] [-size +N字节]\n");
        return 2;
    }
    let root: i64 = argv(1);
    let i: i64 = 2;
    while i < argc() {
        let a: i64 = argv(i);
        if streq(a, "-name") == 1 {
            i = i + 1;
            if i < argc() { strcpy(&pat, argv(i)); }
        } else {
            if streq(a, "-type") == 1 {
                i = i + 1;
                if i < argc() {
                    let c: i64 = load8(argv(i));
                    if c == 102 { want_type = 1; }   # f
                    if c == 100 { want_type = 2; }   # d
                }
            } else {
                if streq(a, "-size") == 1 {
                    i = i + 1;
                    if i < argc() {
                        let s: i64 = argv(i);
                        if load8(s) == 43 {   # '+'
                            let nb: [24] byte = 0;
                            strcpy(&nb, s + 1);
                            # 手动 atoi
                            let v: i64 = 0;
                            let k: i64 = 0;
                            while load8(&nb + k) >= 48 && load8(&nb + k) <= 57 {
                                v = v * 10 + (load8(&nb + k) - 48);
                                k = k + 1;
                            }
                            min_size = v;
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    if exists(root) != 1 {
        print("qyfind: 不存在: "); print(root); print("\n");
        return 2;
    }
    if is_dir(root) == 1 {
        strcpy(&paths, root);
        find_dir(0);
    } else {
        # 单文件：直接对文件名匹配
        basename(root, &path_now);
        hit(&path_now, 0, root);
    }
    if found > 0 { return 0; }
    return 1;
}
