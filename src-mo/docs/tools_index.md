# 工具索引

版本 1.9.0

## 构建与验证

| 工具 | 作用 |
|---|---|
| `make` | 主入口：seed → moc |
| `make sync-check` | 校验 `src/mo/` 拼接产物与 `src/compiler.mo` 一致 |
| `make sync` | 从 `src/mo/` 重新拼接出 `src/compiler.mo` |
| `build.sh` | 底层构建（seed / self） |
| `verify_bootstrap.sh` | 自举三级闭环验证 |
| `tests/run.sh` | 主测试套件 |

## 自检（每一类都针对一种"静默漂移"）

| 工具 | 防的是什么 |
|---|---|
| `tools/projcheck.sh` | **总入口**：下面 5 项 + 拼接一致 + 版本号 + 脏文件，共 8 项 |
| `tools/depcheck.sh` | 标准库缺少自己的 `import`（靠主文件顺带引入才"能编译"） |
| `tools/multibackend_test.sh` | 同一程序在多个后端下退出码不一致 |
| `tools/fmttest.sh` | 格式化改写了代码（判据：代码段逐字节相同 + 幂等） |
| `tools/dbgtest.sh` | `-g` 影响程序行为（判据：开与不开运行结果相同） |
| `tools/codesize.sh` | 优化效果无法量化 |

`projcheck` 是这轮补的。此前每一类漂移都真实发生过：
`src/mo/` 与 `compiler.mo` 漂移过（1.9.0 补的修复差点丢失）、
标准库副本与 `lib/` 漂移过、新库写完无测试引用（matrix / stat 就是）。

**一次性补齐没用，得让它变成红灯。**

## 转译与工程

| 工具 | 作用 |
|---|---|
| `tools/mo2x.mo` | 一份前端 + 14 个发射器（c / cfs* / js / py / perl / java / go / rust / cs / swift / ruby / lua / php） |
| `tools/cross.sh` | 交叉编译：先找 `${TRIPLET}-gcc`，没有就用 `zig cc` |
| `tools/android.sh` | 生成 Android 工程（java / ndk / web 三条路径） |
| `tools/mobuild.sh` | 递归收集 import，打印依赖图 |
| `tools/mo.sh` | 统一命令行驱动（9 个子命令） |
| `tools/fmt.mo` | 格式化（只调缩进与行尾） |
| `tools/install.sh` | 安装到 `$PREFIX` |

## 编辑器与 CI

| 路径 | 内容 |
|---|---|
| `tools/editor/` | Vim 语法高亮、VSCode 语法高亮、LSP 配置片段 |
| `tools/ci/` | GitHub Actions 工作流 |
