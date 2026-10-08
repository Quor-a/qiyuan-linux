# freq —— 统计文件里每个单词出现的次数，按次数从多到少输出
#   用法: freq <文件名>
#
# 这一版用动态数组（lib/vec.mo）存单词与次数，不再有「最多 200 个不同单词」
# 的上限。单词本身在堆上按实际长度分配，也不再有「每个最长 24 字节」的限制。
import "fs.mo";
import "io.mo";
import "str.mo";
import "mem.mo";
import "vec.mo";

var buf: [65536] byte = 0;   # 文件内容
var words: i64 = 0;          # vec：每个元素是一个字符串指针
var counts: i64 = 0;         # vec：每个元素是该单词的出现次数

# 找单词在表里的下标，找不到返回 -1
fn find(w: ptr) -> i64 {
    let i: i64 = 0;
    let n: i64 = vec_len(words);
    while i < n {
        if streq(vec_get(words, i), w) == 1 {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

# 加入新单词：把字符串拷进堆里，长度按需分配
fn add(w: ptr) -> i64 {
    let n: i64 = strlen(w);
    let p: i64 = alloc(n + 1);
    strcpy(p, w);
    vec_push(words, p);
    vec_push(counts, 1);
    return vec_len(words) - 1;
}

fn bump(w: ptr) -> i64 {
    let k: i64 = find(w);
    if k < 0 {
        return add(w);
    }
    vec_set(counts, k, vec_get(counts, k) + 1);
    return k;
}

fn is_word_char(c: i64) -> i64 {
    if c >= 97 {
        if c <= 122 {
            return 1;
        }
    }
    if c >= 65 {
        if c <= 90 {
            return 1;
        }
    }
    if c >= 48 {
        if c <= 57 {
            return 1;
        }
    }
    return 0;
}

# 扫描缓冲区，把连续的字母数字段当作单词。
# 单词先写进局部缓冲（够长即可，长词会被截断到 127 字节），再交 bump。
fn scan(n: i64) -> i64 {
    let i: i64 = 0;
    let tmp: [128] byte = 0;
    while i < n {
        if is_word_char(buf[i]) == 1 {
            let j: i64 = 0;
            while is_word_char(buf[i]) == 1 {
                let c: i64 = buf[i];
                # 统一转小写，便于归并 The / the
                if c >= 65 {
                    if c <= 90 {
                        c = c + 32;
                    }
                }
                if j < 127 {
                    tmp[j] = c;
                    j = j + 1;
                }
                i = i + 1;
            }
            tmp[j] = 0;
            bump(&tmp);
        } else {
            i = i + 1;
        }
    }
    return vec_len(words);
}

# 选择排序：按次数降序，次数相同按字典序
fn sort_by_count() -> i64 {
    let n: i64 = vec_len(counts);
    let i: i64 = 0;
    while i < n {
        let best: i64 = i;
        let j: i64 = i + 1;
        while j < n {
            let a: i64 = vec_get(counts, j);
            let b: i64 = vec_get(counts, best);
            if a > b {
                best = j;
            } else {
                if a == b {
                    if strcmp(vec_get(words, j), vec_get(words, best)) < 0 {
                        best = j;
                    }
                }
            }
            j = j + 1;
        }
        if best != i {
            swap(i, best);
        }
        i = i + 1;
    }
    return 0;
}

fn swap(a: i64, b: i64) -> i64 {
    let tw: i64 = vec_get(words, a);
    vec_set(words, a, vec_get(words, b));
    vec_set(words, b, tw);
    let tc: i64 = vec_get(counts, a);
    vec_set(counts, a, vec_get(counts, b));
    vec_set(counts, b, tc);
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("usage: freq <file>\n");
        return 2;
    }
    heap_init();
    words = vec_new();
    counts = vec_new();

    let n: i64 = read_file(argv(1), &buf, 65536);
    if n < 0 {
        print("freq: cannot open ");
        print(argv(1));
        print_nl();
        return 1;
    }
    scan(n);
    sort_by_count();

    let i: i64 = 0;
    let total: i64 = vec_len(counts);
    while i < total {
        print_i64(vec_get(counts, i));
        print(" ");
        print(vec_get(words, i));
        print_nl();
        i = i + 1;
    }
    return 0;
}
