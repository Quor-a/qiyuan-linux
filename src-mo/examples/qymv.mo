# qymv —— 文件移动/重命名工具（墨语言实战工具 #12）
#
# 用法:
#   qymv <源> <目标>            移动或重命名（同盘 rename，跨盘 copy+unlink）
#   qymv -f <源> <目标>         目标存在时强制覆盖（默认拒绝）
#
# 实战压测点：rename 系统调用（同盘原子移动）、跨设备判断（EXDEV=18 →
# 降级 copy+unlink）、目录创建（mkdir_p 递归建目标父目录）、
# copy 循环（65KB 分块，尺寸校验）、unlink/rmdir 清理。
import "io.mo";
import "fs.mo";
import "str.mo";
import "dir.mo";

var fbuf: [65536] byte = 0;
var parent: [1024] byte = 0;

# 把路径截出父目录（最后一个 / 之前），无 / 返回 -1
fn parent_of(p: i64, dst: i64) -> i64 {
    let len: i64 = strlen(p);
    let i: i64 = len - 1;
    while i >= 0 {
        if load8(p + i) == 47 {
            if i == 0 {
                store8(dst, 47);
                store8(dst + 1, 0);
                return 0;
            }
            memcpy(dst, p, i);
            store8(dst + i, 0);
            return 0;
        }
        i = i - 1;
    }
    return 0 - 1;
}

# 递归建目录（mkdir_p，dir.mo 提供 mkdir）
fn mkdir_p(p: i64) -> i64 {
    if strlen(p) == 0 { return 0; }
    let r: i64 = mkdir(p, 493);   # 0755
    if r == 0 { return 0; }
    let e: i64 = 0 - r;
    if e == 17 { return 0; }      # EEXIST
    if e == 2 {                   # ENOENT → 先建父目录
        if parent_of(p, &parent) == 0 {
            mkdir_p(&parent);
            r = mkdir(p, 493);
            if r == 0 { return 0; }
            if 0 - r == 17 { return 0; }
        }
        return 0 - 1;
    }
    return 0 - 1;
}

# 跨设备拷贝（分块 + 尺寸校验），成功后删源
fn copy_over(src: i64, dst: i64) -> i64 {
    let s: i64 = stat_size(src);
    if s < 0 { return 0 - 1; }
    let fd1: i64 = fopen(src, 0, 0);
    if fd1 < 0 { return 0 - 1; }
    let fd2: i64 = fopen(dst, 577, 438);   # O_WRONLY|O_CREAT|O_TRUNC, 0666
    if fd2 < 0 {
        fclose(fd1);
        return 0 - 1;
    }
    let total: i64 = 0;
    while 1 == 1 {
        let n: i64 = fread(fd1, &fbuf, 65536);
        if n <= 0 { break; }
        let w: i64 = fwrite(fd2, &fbuf, n);
        if w != n {
            print("qymv: 写入不完整\n");
            fclose(fd1);
            fclose(fd2);
            return 0 - 1;
        }
        total = total + n;
    }
    fclose(fd1);
    fclose(fd2);
    if total != s {
        print("qymv: 尺寸不符 ");
        print_i64(total);
        print(" != ");
        print_i64(s);
        print("\n");
        return 0 - 1;
    }
    unlink(src);
    return 0;
}

fn main() -> i64 {
    let force: i64 = 0;
    let a1: i64 = 0;
    if argc() < 3 {
        print("用法: qymv [-f] <源> <目标>\n");
        return 1;
    }
    let idx: i64 = 1;
    a1 = argv(1);
    if streq(a1, "-f") == 1 {
        force = 1;
        idx = 2;
    }
    if argc() < idx + 2 {
        print("用法: qymv [-f] <源> <目标>\n");
        return 1;
    }
    let src: i64 = argv(idx);
    let dst: i64 = argv(idx + 1);
    if stat_size(src) < 0 {
        print("qymv: 源不存在: ");
        print(src);
        print("\n");
        return 1;
    }
    # 目标存在且未 -f → 拒绝覆盖
    if force == 0 && stat_size(dst) >= 0 {
        print("qymv: 目标已存在（-f 覆盖）: ");
        print(dst);
        print("\n");
        return 1;
    }
    # 确保目标父目录存在（重命名到新目录场景）
    if parent_of(dst, &parent) == 0 {
        if stat_mode(&parent) < 0 {
            mkdir_p(&parent);
        }
    }
    # 先试同盘 rename（原子）
    let r: i64 = rename(src, dst);
    if r == 0 {
        print("moved ");
        print(src);
        print(" -> ");
        print(dst);
        print("\n");
        return 0;
    }
    let e: i64 = 0 - r;
    if e == 18 {
        # EXDEV 跨设备 → copy+unlink
        if copy_over(src, dst) == 0 {
            print("copied+removed ");
            print(src);
            print(" -> ");
            print(dst);
            print("\n");
            return 0;
        }
        return 1;
    }
    print("qymv: 失败 errno=");
    print_i64(e);
    print("\n");
    return 1;
}
