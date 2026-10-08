# Android 与交叉编译

版本 1.8.0（2026-10-08）

## 一、Android：三条上手机路径

```bash
./tools/android.sh <app.mo> <包名> [java|ndk|web] [-o 目录]
```

| 模式 | 原理 | 生成物 |
|---|---|---|
| **java** | Java 后端 → `.java` → ART（Android 运行时） | `MainActivity.java` + Gradle 工程 |
| **ndk** | C 后端 → `.c` → NDK 编译成 `.so` | `native.c` + `jni_bridge.c` + `CMakeLists.txt` |
| **web** | JS 后端 → `.js` → WebView | `assets/app.js` + `index.html` |

三条都用**同一个前端**，只是发射器不同 —— 这就是多后端的意义。

### 必须说清楚的一点

**本机没有 Android SDK / NDK，所以只生成工程，没有构建 APK。**
生成后需要：

```bash
export ANDROID_HOME=~/Android/Sdk
cd <目录> && ./gradlew assembleDebug
```

这是刻意写进 README 的，避免"看起来构建过了"。

`java` 模式是最现实的路径：Android 应用本来就是跑在 ART 上的 Java 字节码，
墨语言的 Java 后端产物可以直接作为应用逻辑层。

## 二、交叉编译

```bash
./tools/cross.sh <app.mo> <triplet> [-o out]
```

原理：原生后端只会 x86-64 Linux，要到别的架构就走 C 后端：

```
.mo --mo2x c--> .c --${TRIPLET}-gcc--> 目标平台可执行文件
```

支持 triplet（有编译器就编，没有就明确报错 + 给出安装命令）：
`aarch64-linux-gnu`、`arm-linux-gnueabihf`、`riscv64-linux-gnu`、
`x86_64-linux-musl`、`aarch64-linux-android`、`armv7a-linux-androideabi`、
`x86_64-w64-mingw32`、`x86_64-apple-darwin`。

**本机实测：没有任何交叉工具链**（`gcc-aarch64-linux-gnu` 装不上，
源里没有）。所以脚本在无工具链时会：仍然生成 C 源码 + 打印安装提示 + 退出码 2。
不会假装成功。
