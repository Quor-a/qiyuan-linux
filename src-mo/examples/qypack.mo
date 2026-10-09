# qypack —— 启元复杂包管理器（用墨语言写的实战工具 #3）
#
# 目标：一个真正复杂的包管理前端，实战压测语言能力：
#   1. 读 qyp 包元数据（JSON 解析）
#   2. 依赖解析：递归+循环检测（vec/map/栈）
#   3. 安装计划：拓扑排序
#   4. 仓库索引：目录扫描+内存索引
#   5. 事务模拟：undo 日志
#
#   ./qypack <命令> [参数]
#     index <仓库目录>          扫描仓库建索引
#     resolve <包名>            解析依赖并输出安装顺序
#     plan <依赖描述文件>       生成安装计划
#
# 实战方法论：每发现一个语言/库缺失，记录到 docs/mo_gaps.md 并修复。
import "io.mo";
import "fs.mo";
import "str.mo";
import "json.mo";
import "dir.mo";

# ---------- 包数据库（内存索引） ----------
# 最多 256 个包，每个包：名字、版本、依赖列表（最多 8 个）
var PKG_MAX: i64 = 256;
var DEP_MAX: i64 = 8;

var pkg_names: [8192] byte = 0;      # 256 * 32
var pkg_versions: [8192] byte = 0;   # 256 * 32
var pkg_depcounts: [256] byte = 0;
var pkg_deps: [2048] byte = 0;       # 256 * 8 依赖下标（0xFF=无）
var dep_names: [131072] byte = 0;    # 256 * 8 * 64 依赖名字暂存（索引期）
var pkg_count: i64 = 0;

var name_tmp: [64] byte = 0;
var ver_tmp: [64] byte = 0;
var jbuf: [32768] byte = 0;
var val_tmp: [512] byte = 0;
var dep_tmp: [64] byte = 0;
var pathbuf: [4096] byte = 0;
var dirent_names: [64000] byte = 0;
var dirent_types: [250] byte = 0;

# ---------- 名字→下标 映射（线性查，够用） ----------
fn pkg_find(name: i64) -> i64 {
    let i: i64 = 0;
    while i < pkg_count {
        if streq(&pkg_names + i * 32, name) == 1 { return i; }
        i = i + 1;
    }
    return -1;
}

fn pkg_add(name: i64, ver: i64) -> i64 {
    if pkg_count >= PKG_MAX { return -1; }
    let slot: i64 = pkg_count;
    strcpy(&pkg_names + slot * 32, name);
    strcpy(&pkg_versions + slot * 32, ver);
    pkg_depcounts[slot] = 0;
    let d: i64 = 0;
    while d < DEP_MAX {
        store8(&pkg_deps + slot * 8 + d, 255);
        d = d + 1;
    }
    pkg_count = pkg_count + 1;
    return slot;
}

fn pkg_add_dep(slot: i64, depidx: i64) -> i64 {
    let c: i64 = pkg_depcounts[slot];
    if c >= DEP_MAX { return -1; }
    store8(&pkg_deps + slot * 8 + c, depidx);
    pkg_depcounts[slot] = c + 1;
    return 0;
}

# ---------- 索引：扫仓库目录，读每个 .qyp 的元数据 JSON ----------
# qyp 文件名约定: name-version-release.arch.qyp
# 元数据 JSON 旁路文件: 同目录 meta/<name>.json（简化：我们直接读 .json）
fn cmd_index(repodir: i64) -> i64 {
    let n: i64 = dir_list(repodir, &dirent_names, &dirent_types, 256, 249);
    if n < 0 {
        print("错误：打不开仓库目录\n");
        return 1;
    }
    print("扫描 ");
    print(repodir);
    print(" (");
    print_i64(n);
    print(" 条目)\n");
    let i: i64 = 0;
    while i < n {
        let nm: i64 = &dirent_names + i * 256;
        # 只处理 .json 元数据
        if strstr(nm, ".json") > 0 {
            strcpy(&pathbuf, repodir);
            strcat(&pathbuf, "/");
            strcat(&pathbuf, nm);
            let sz: i64 = read_file(&pathbuf, &jbuf, 32767);
            if sz >= 0 {
                store8(&jbuf + sz, 0);
                if json_str(&jbuf, "name", &val_tmp) == 1 {
                    strcpy(&name_tmp, &val_tmp);
                } else {
                    strcpy(&name_tmp, "?");
                }
                if json_str(&jbuf, "version", &val_tmp) == 1 {
                    strcpy(&ver_tmp, &val_tmp);
                } else {
                    strcpy(&ver_tmp, "0");
                }
                let slot: i64 = pkg_add(&name_tmp, &ver_tmp);
                if slot >= 0 {
                    # 解析 depends 字符串数组，先存名字，索引完成后换成下标
                    let d: i64 = 0;
                    while d < 8 {
                        if json_array_str(&jbuf, "depends", d, &val_tmp, 512) == 1 {
                            store8(&pkg_deps + slot * 8 + d, 254);    # 标记：有名字待解析
                            strcpy(&dep_names + slot * 512 + d * 64, &val_tmp);
                            pkg_depcounts[slot] = d + 1;
                            d = d + 1;
                        } else {
                            d = 8;
                        }
                    }
                    print("  + ");
                    print(&name_tmp);
                    print("-");
                    print(&ver_tmp);
                    print("\n");
                }
            }
        }
        i = i + 1;
    }
    print("索引完成: ");
    print_i64(pkg_count);
    print(" 个包\n");
    # 第二遍：把依赖名字换成下标
    let s2: i64 = 0;
    while s2 < pkg_count {
        let d2: i64 = 0;
        while d2 < pkg_depcounts[s2] {
            if load8(&pkg_deps + s2 * 8 + d2) == 254 {
                let di: i64 = pkg_find(&dep_names + s2 * 8 * 64 + d2 * 64);
                if di < 0 {
                    print("!! 依赖不存在: ");
                    print(&pkg_names + s2 * 32);
                    print(" -> ");
                    print(&dep_names + s2 * 8 * 64 + d2 * 64);
                    print("\n");
                    return 1;
                }
                store8(&pkg_deps + s2 * 8 + d2, di);
            }
            d2 = d2 + 1;
        }
        s2 = s2 + 1;
    }
    return 0;
}

# ---------- 依赖解析：DFS + 三色标记（0白 1灰 2黑） ----------
var color: [256] byte = 0;
var order: [256] byte = 0;      # 拓扑序（安装顺序）
var order_n: i64 = 0;
var cycle_flag: i64 = 0;

fn dfs(idx: i64) -> i64 {
    if color[idx] == 1 {
        print("!! 循环依赖: ");
        print(&pkg_names + idx * 32);
        print("\n");
        cycle_flag = 1;
        return -1;
    }
    if color[idx] == 2 { return 0; }
    color[idx] = 1;
    let dc: i64 = pkg_depcounts[idx];
    let d: i64 = 0;
    while d < dc {
        let dep: i64 = load8(&pkg_deps + idx * 8 + d);
        if dep != 255 {
            if dfs(dep) < 0 { return -1; }
        }
        d = d + 1;
    }
    color[idx] = 2;
    order[order_n] = idx;
    order_n = order_n + 1;
    return 0;
}

fn cmd_resolve(name: i64) -> i64 {
    let idx: i64 = pkg_find(name);
    if idx < 0 {
        print("!! 包不存在: ");
        print(name);
        print("\n");
        return 1;
    }
    order_n = 0;
    cycle_flag = 0;
    let i: i64 = 0;
    while i < pkg_count { color[i] = 0; i = i + 1; }
    if dfs(idx) < 0 {
        print("!! 解析失败（循环依赖）\n");
        return 1;
    }
    print("安装顺序 (");
    print_i64(order_n);
    print(" 个包):\n");
    let j: i64 = 0;
    while j < order_n {
        let k: i64 = order[j];
        print("  ");
        print_i64(j + 1);
        print(". ");
        print(&pkg_names + k * 32);
        print("-");
        print(&pkg_versions + k * 32);
        print("\n");
        j = j + 1;
    }
    return 0;
}

# ---------- install：按拓扑序逐包安装（模拟事务 + undo 日志） ----------
# 用法: qypack install <仓库目录> <目标根> <包名>
# 每包"安装"= 在 <目标根>/installed/ 落一个 .marker 文件；事务日志写
# <目标根>/transactions/<时间戳>.txn（逐行记包名，最后一行 COMMITTED）。
# undo 读最近一个 COMMITTED 事务，反向删除 marker，标记 ROLLED_BACK。
var txn_name: [128] byte = 0;
var txn_path: [256] byte = 0;
var ins_dir: [512] byte = 0;

fn strcat2(dst: i64, a: i64, b: i64) -> i64 {
    strcpy(dst, a);
    strcat(dst, b);
    return 0;
}

fn write_str_file(path: i64, content: i64) -> i64 {
    let fd: i64 = fopen(path, 577, 420);
    if fd < 0 { return 0 - 1; }
    fwrite(fd, content, strlen(content));
    fclose(fd);
    return 0;
}

fn append_file(path: i64, content: i64, n: i64) -> i64 {
    let fd: i64 = fopen(path, 1025, 420);    # O_WRONLY|O_APPEND
    if fd < 0 { return 0 - 1; }
    fwrite(fd, content, n);
    fclose(fd);
    return 0;
}

fn file_exists(path: i64) -> i64 {
    let fd: i64 = fopen(path, 0, 0);
    if fd < 0 { return 0; }
    fclose(fd);
    return 1;
}

fn make_dir(path: i64) -> i64 {
    return mkdir(path, 493);
}

fn delete_file(path: i64) -> i64 {
    return unlink(path);
}

fn cmd_install(repodir: i64, root: i64, name: i64) -> i64 {
    if cmd_index(repodir) != 0 { return 1; }
    let idx: i64 = pkg_find(name);
    if idx < 0 {
        print("!! 包不存在: ");
        print(name);
        print("\n");
        return 1;
    }
    # 已安装检查
    strcat2(&txn_path, root, "/installed/");
    strcat(&txn_path, &pkg_names + idx * 32);
    strcat(&txn_path, ".marker");
    if file_exists(&txn_path) == 1 {
        print("!! 已安装: ");
        print(&pkg_names + idx * 32);
        print("\n");
        return 1;
    }
    # 依赖解析
    order_n = 0;
    cycle_flag = 0;
    let i: i64 = 0;
    while i < pkg_count { color[i] = 0; i = i + 1; }
    if dfs(idx) < 0 {
        print("!! 解析失败（循环依赖）\n");
        return 1;
    }
    # 事务目录与日志文件
    strcpy(&txn_name, "txn-");
    strcat(&txn_name, &pkg_names + idx * 32);
    strcat2(&txn_path, root, "/transactions/");
    mkdir_p(&txn_path);
    strcat(&txn_path, &txn_name);
    strcat(&txn_path, ".txn");
    if write_str_file(&txn_path, "") < 0 {
        print("!! 无法创建事务日志\n");
        return 1;
    }
    print("事务 ");
    print(&txn_name);
    print(" 开始（install）\n");
    # 按拓扑序逐包安装
    let j: i64 = 0;
    while j < order_n {
        let k: i64 = order[j];
        strcat2(&ins_dir, root, "/installed/");
        mkdir_p(&ins_dir);
        strcat(&ins_dir, &pkg_names + k * 32);
        strcat(&ins_dir, ".marker");
        # marker 内容 = 包名-版本
        strcpy(&val_tmp, &pkg_names + k * 32);
        strcat(&val_tmp, "-");
        strcat(&val_tmp, &pkg_versions + k * 32);
        strcat(&val_tmp, "\n");
        if write_str_file(&ins_dir, &val_tmp) < 0 {
            print("!! 安装失败: ");
            print(&pkg_names + k * 32);
            print("（事务中止，可 undo）\n");
            return 1;
        }
        # 追加到事务日志
        strcat2(&val_tmp, &pkg_names + k * 32, "\n");
        append_file(&txn_path, &val_tmp, strlen(&val_tmp));
        print("  + ");
        print(&pkg_names + k * 32);
        print("-");
        print(&pkg_versions + k * 32);
        print("\n");
        j = j + 1;
    }
    append_file(&txn_path, "COMMITTED\n", 10);
    print("事务 ");
    print(&txn_name);
    print(" 已提交（");
    print_i64(order_n);
    print(" 个包）\n");
    return 0;
}

# 目录逐级创建：a/b/c → 依次 mkdir
fn mkdir_p(path: i64) -> i64 {
    let i: i64 = 1;
    while load8(path + i) != 0 {
        if load8(path + i) == 47 {
            store8(path + i, 0);
            make_dir(path);
            store8(path + i, 47);
        }
        i = i + 1;
    }
    return make_dir(path);
}

# ---------- undo：回滚最近一个 COMMITTED 事务 ----------
fn cmd_undo(root: i64) -> i64 {
    strcat2(&txn_path, root, "/transactions");
    let n: i64 = dir_list(&txn_path, &dirent_names, &dirent_types, 256, 249);
    if n <= 0 {
        print("!! 没有事务可回滚\n");
        return 1;
    }
    # 找字典序最大的 .txn（时间戳命名即最新）
    let best: i64 = 0 - 1;
    strcpy(&name_tmp, "");
    let i: i64 = 0;
    while i < n {
        let nm: i64 = &dirent_names + i * 256;
        if strstr(nm, ".txn") > 0 {
            if best < 0 || strcmp(&name_tmp, nm) < 0 {
                best = i;
                strcpy(&name_tmp, nm);
            }
        }
        i = i + 1;
    }
    if best < 0 {
        print("!! 没有事务文件\n");
        return 1;
    }
    strcat2(&txn_path, root, "/transactions/");
    strcat(&txn_path, &name_tmp);
    let sz: i64 = read_file(&txn_path, &jbuf, 32000);
    if sz < 0 {
        print("!! 读不到事务日志\n");
        return 1;
    }
    store8(&jbuf + sz, 0);
    if strstr(&jbuf, "COMMITTED") < 0 {
        print("!! 最近事务未提交，无可回滚内容\n");
        return 1;
    }
    print("回滚事务 ");
    print(&name_tmp);
    print("：\n");
    # 逐行解析（拷贝到 line 缓冲，避免原地改写破坏 strlen 语义）
    let i2: i64 = 0;
    let l2: i64 = 0;
    let cnt: i64 = 0;
    while i2 <= sz {
        let c: i64 = load8(&jbuf + i2);
        if c == 10 || c == 0 {
            store8(&val_tmp + l2, 0);
            if l2 > 0 {
                if streq(&val_tmp, "COMMITTED") != 1 {
                    strcat2(&ins_dir, root, "/installed/");
                    strcat(&ins_dir, &val_tmp);
                    strcat(&ins_dir, ".marker");
                    if delete_file(&ins_dir) == 0 {
                        print("  - ");
                        print(&val_tmp);
                        print("\n");
                        cnt = cnt + 1;
                    } else {
                        print("  ! 删除失败: ");
                        print(&val_tmp);
                        print("\n");
                    }
                }
            }
            l2 = 0;
        } else {
            store8(&val_tmp + l2, c);
            l2 = l2 + 1;
        }
        i2 = i2 + 1;
    }
    strcat(&txn_path, ".rolledback");
    write_str_file(&txn_path, "ROLLED_BACK\n");
    print("回滚完成（");
    print_i64(cnt);
    print(" 个包）\n");
    return 0;
}

# ---------- 主入口 ----------
fn main() -> i64 {
    print("qypack —— 墨语言写的复杂包管理器\n\n");
    if argc() < 2 {
        print("用法:\n");
        print("  qypack index <仓库目录>\n");
        print("  qypack resolve <包名>   (先 index)\n");
        print("  qypack pipeline <仓库目录> <包名>   一步: 建索引+解析依赖\n");
        return 1;
    }
    let cmd: i64 = argv(1);
    if streq(cmd, "index") == 1 {
        if argc() < 3 { print("缺参数\n"); return 1; }
        return cmd_index(argv(2));
    }
    if streq(cmd, "resolve") == 1 {
        if argc() < 3 { print("缺参数\n"); return 1; }
        return cmd_resolve(argv(2));
    }
    if streq(cmd, "pipeline") == 1 {
        if argc() < 4 { print("缺参数\n"); return 1; }
        let r: i64 = cmd_index(argv(2));
        if r != 0 { return r; }
        print("\n");
        return cmd_resolve(argv(3));
    }
    if streq(cmd, "install") == 1 {
        if argc() < 5 { print("用法: qypack install <仓库目录> <目标根> <包名>\n"); return 1; }
        return cmd_install(argv(2), argv(3), argv(4));
    }
    if streq(cmd, "undo") == 1 {
        if argc() < 3 { print("用法: qypack undo <目标根>\n"); return 1; }
        return cmd_undo(argv(2));
    }
    print("未知命令\n");
    return 1;
}
