# 墨语言 × 启元系统 开发手册

版本：配合墨语言 1.10.0 · 启元 Linux 1.9.x
定位：在启元系统上用墨语言做系统开发的实操手册——边用边补，遇到缺失就修语言或补库。

---

## 一、安装与第一条命令

```bash
# qypkg 安装（旧包管理继续可用）
qypkg install mo

# 装完即有：
#   /usr/bin/moc         编译器（墨语言自举产物，ELF 原生）
#   /usr/bin/mo          工具链包装器（build/run/test/boot/fmt/size/info）
#   /usr/lib/mo/*.mo     系统标准库（18 个模块）
#   /usr/share/mo/examples/  示例程序
```

## 二、五分钟上手

写 `hello.mo`：

```mo
import "io.mo";

fn main() -> i64 {
    print("你好，启元！\n");
    return 0;
}
```

编译运行（任何目录都行，编译器自动搜 `/usr/lib/mo/`）：

```bash
moc hello.mo hello.elf
./hello.elf

# 或者一步到位（脚本式体验）：
mo run hello.mo
```

## 三、启元系统开发的四类典型任务

### 3.1 系统组件 / 守护进程

墨语言直接走 Linux syscall，不依赖 libc——这让它特别适合写启元的
系统组件（比 C 少了内存安全问题，比 Python 少了运行时依赖）。

可用能力（标准库）：

| 需求 | 库 | 说明 |
|---|---|---|
| 文件读写 | `fs.mo` | fopen/fread/fwrite/fclose/read_file |
| 目录遍历 | `dir.mo` | getdents64 遍历、stat、mkdir/rename/unlink/chmod |
| TCP 网络 | `net.mo` | socket/bind/listen/accept/send/recv（服务端+客户端） |
| 伪终端 | `pty.mo` | fork/exec/wait/kill、窗口大小 |
| 进程 | 直接 syscall | getpid/kill/fork/exec |
| 内核信息 | 直接 syscall | uname/sysinfo |

现成例子：`examples/httpd.mo` 是一个每连接 fork 的并发 HTTP 服务器，
`examples/hwinfo.mo` 打印内核/CPU/内存信息，
`examples/qycheck.mo` 是真实交付的 qyp 元数据校验器
（JSON 解析 + 文件 IO + 字符串处理 + 退出码语义，已在启元构建机上实战验证：
缺字段 exit=1 / 全通过 exit=0）。

```bash
# 参考：起一个本地服务
mo run /usr/share/mo/examples/httpd.mo 8080
curl http://127.0.0.1:8080/
```

### 3.2 写启元的软件包工具

启元的包管理生态（qypkg 是旧包管理，继续支持；新工具推荐用墨语言写）：

- 配方解析、依赖计算、校验和检查这类纯逻辑，用 `vec.mo`（动态数组）+
  `map.mo`（字符串映射）+ `json.mo`（解析 qyp 元数据）组合就够
- 包文件是 tar/gzip——`archive.mo` 直接可读可写
- 签名校验用 `hmac.mo`（HMAC-SHA256，RFC 4231 向量验证过）

开发范式（qybuild 兼容思路）：

```
mypkg/
  mo.mod          # 项目清单（tools/manifest.mo 负责解析）
  src/main.mo
  tests/
```

`mo.mod` 示例：

```
[package]
name = "qy-something"
version = "0.1.0"

[build]
entry = "src/main.mo"
```

### 3.3 写开发工具（自举红利）

墨语言的编译器、格式化工具 `fmt.mo`、多后端转换器 `mo2x` 全是墨语言
自己写的——你想写 IDE 语言服务、linter、代码生成器，语言本身已经
证明了这条路能走通。参考 `tools/` 下现成实现：

| 工具 | 学什么 |
|---|---|
| `tools/fmt.mo` | 词法级代码处理（保证代码段字节不变） |
| `tools/manifest.mo` | 配置文件解析 |
| `tools/mo2x.mo` | 一份前端多个发射器（C/JS/Python 后端） |

### 3.4 与启元系统的配合

- **qypkg 打包你的墨程序**：编译出的静态 ELF 零依赖，qyp 包里放
  `usr/bin/xxx` 即可，不需要链接器黑名单、不需要依赖闭包
- **qyinit 单元**：墨程序可作常驻服务，配 systemd 式单元或 init 脚本
- **交叉场景**：四后端中的 C 后端可以产出给其他架构/系统用的代码
  （`mo2x prog.mo c > prog.c && gcc prog.c`）

## 四、语言速查

```mo
# 变量
var g: [8] i64 = 0;        # 全局数组
let a: [16] i64;           # 局部数组
let s: i64 = "hello"[1];   # 字符串下标 → byte
let b: byte = 65;          # 1 字节
let p: ptr = &x;           # 字节指针，按字节算术

# 控制流
if x > 0 { } else if x == 0 { } else { }
while i < n { break; continue; }

# 结构体
struct Point { x: i64, y: i64 }
let p2: Point;  p2.x = 1;
p2 = p1;              # 整体深拷贝
s.f += 1;             # 复合赋值（+= -= *= /= %= &= |= ^= <<= >>=）

# 函数（缺 return 会在编译期警告/拦截）
fn add(a: i64, b: i64) -> i64 { return a + b; }

# import（按顺序搜：原样 → ./lib/ → ../lib/ → /usr/lib/mo/）
import "io.mo";
import "vec.mo";
```

诊断能力（编译期拦截，不静默）：数组常量下标越界、缺 return、
未使用变量警告、运行期数组越界报错并退出 1。

## 五、标准库 18 模块一览

| 模块 | 内容 |
|---|---|
| `io.mo` | print / print_i64 / print_hex |
| `str.mo` | strlen/streq/strcpy/strcmp/memset/memcpy/strcat/strchr/atoi/utoa |
| `fs.mo` | fopen/fread/fwrite/fclose/fputs/read_file |
| `dir.mo` | 目录遍历(getdents64)/stat/mkdir/rename/unlink/chmod |
| `net.mo` | TCPv4 服务端+客户端（socket 全家桶） |
| `pty.mo` | 伪终端主从端/fork/exec/wait/kill |
| `vec.mo` | 动态数组 |
| `map.mo` | 字符串键映射 |
| `json.mo` | JSON 解析 |
| `archive.mo` | tar 打包解压 + gzip（系统工具可读） |
| `crypto.mo` | SHA-256 / CRC32 / Base64 / ChaCha20 |
| `hmac.mo` | HMAC-SHA256 + 常量时间比较 |
| `binfmt.mo` | ELF/gzip/tar/PNG/ZIP/PDF 等魔数识别、ELF 头解析 |
| `mem.mo` | bump 分配器 |
| `log.mo` | 日志：级别过滤/文件输出/环形缓冲 |
| `assert.mo` | 断言测试框架 |
| `stat.mo` | 统计 |
| `matrix.mo` | 矩阵 |

## 六、实战驱动的完善闭环（工作方法）

1. **先写真实工具**，不预先设计——遇到卡壳就是语言的缺失点
2. 缺失分三类处理：
   - 语言能力缺 → 改编译器（`src/mo/part*.mo`），遵守双改规则（seed 与 mo 同步改）
   - 标准库缺 → 新增 `lib/xxx.mo` + tests/ 用例
   - 文档与实际不符 → 修文档（历史上发生过"文档说没实现，其实早实现了"）
3. 每次改动跑三件套：`bash verify_bootstrap.sh`（自举 md5 一致）、
   `bash tests/run.sh`（当前 99 项）、`tools/projcheck.sh`（8 项漂移自检）
4. 补丁走 qypkg：改完的 mo 包 `qybuild mo --force && qypkg install mo`

## 七、已知边界（诚实清单）

- 寄存器分配未完成（需先引入 IR），性能上不及 gcc -O2
- 交叉编译/APK/多架构/GPU 需新后端（见 docs/capability_matrix.md）
- 四后端中 JS/Python 仅覆盖算法子集
- 字符串是字节序列，UTF-8 处理需自己按 byte 操作（标准库尚无 unicode 模块）
- 浮点支持有限，当前以整数为中心

### 实战抓到的两大陷阱（写递归/解析代码前必读）

1. **全局缓冲不可重入**。递归函数里凡是调用 `dir_list`、`read_file` 等向全局
   缓冲写数据的函数，子调用返回后外层缓冲已被覆盖。修法：按深度分槽
   （`names_at(depth)` 返回该层专属缓冲），见 `examples/qydu.mo` 的 scan()。
2. **原地截断破坏 strlen**。对缓冲区 `store8(p, 0)` 截断后再
   `p = p + strlen(p) + 1` 推进行指针，行内容全变空。修法：逐字节拷贝到
   行缓冲再处理，见 `examples/qypack.mo` 的 cmd_undo()。

## 八、学习资源

- `docs/tutorial.md` 入门教程
- `examples/` 九个真实程序（wc/grep/sort/freq/httpd/hwinfo/calc/plot/bubble_sort）
- `CONTRIBUTING.md` 改编译器的双改规则与调试技巧
- `docs/phase*_report.md` 各阶段验收报告
