"""rathole —— Rust 高性能内网穿透（资源受限设备首选）

许可证：Apache-2.0
设计依据：用户 2026-10-08 内网穿透清单（首批进仓库二选一之二）。
单二进制 ~2MB（release + strip），内存占用个位数 MB，
适合软路由/树莓派/老旧机器长期跑。
"""

name = "rathole"
version = "0.5.0"
release = 1
summary = "Rust 高性能内网穿透（轻量，路由器/树莓派友好）"
license = "Apache-2.0"

source = ["https://github.com/rapiz1/rathole/archive/refs/tags/v0.5.0.tar.gz"]
sha256 = ["c8698dc507c4c2f7e0032be24cac42dd6656ac1c52269875d17957001aa2de41"]
checksum_pending = False

depends = []
makedepends = []
provides = []

requires_build_machine = True
network = True
compression = "gz"


def build(ctx):
    ctx.log("Rust release 构建（--release + strip，产出单二进制）")
    # 沙箱把 HOME 净化成 /tmp，rustup/cargo 找不到工具链 → 显式指回宿主
    ctx.env("RUSTUP_HOME", "/home/agentuser/.rustup")
    ctx.env("CARGO_HOME", "/home/agentuser/.cargo")
    ctx.env("PATH", "/home/agentuser/.cargo/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    # rathole 0.5.0 依赖的旧 time 0.3.29 与 rust 1.99 不兼容（E0282），
    # 锁定 rust 1.80.0 构建
    ctx.env("RUSTUP_TOOLCHAIN", "1.80.0")
    ctx.env("CARGO_NET_GIT_FETCH_WITH_CLI", "true")
    # 模块依赖走国内镜像（断网沙箱里拉不到 crates.io）
    ctx.run("mkdir -p .cargo && printf '%s\\n' "
            "'[source.crates-io]' "
            "'replace-with = \"ustc\"' "
            "'[source.ustc]' "
            "'registry = \"sparse+https://mirrors.ustc.edu.cn/crates.io-index/\"' "
            "> .cargo/config.toml")
    # strip_components=1 后源码树顶层被剥掉，Cargo.toml 直接在 src 下
    # rathole 0.5.0 锁的 time 0.3.29 在 rustc≥1.80 上 E0282（推断变更），
    # 升到 0.3.36 修复
    ctx.run("cargo update -p time --precise 0.3.36")
    ctx.run("cargo build --release --workspace")
    ctx.run("strip target/release/rathole")
    ctx.run("target/release/rathole --help | head -3")


def package(ctx):
    ctx.run("mkdir -p {0}/usr/bin {0}/etc/rathole "
            "{0}/usr/share/doc/rathole".format(ctx.destdir))
    ctx.run("install -m755 target/release/rathole "
            "{}/usr/bin/rathole".format(ctx.destdir))
    # 最小客户端/服务端 TOML（rathole 客户端和服务端是同一个二进制）
    ctx.run("cat > {0}/etc/rathole/client.toml <<'EOF'\n"
            "# rathole 客户端（内网机器上跑）\n"
            "[client]\n"
            "remote_addr = \"你的公网服务器:2333\"\n"
            "\n"
            "[client.services.ssh]\n"
            "local_addr = \"127.0.0.1:22\"\n"
            "EOF".format(ctx.destdir))
    ctx.run("cat > {0}/etc/rathole/server.toml <<'EOF'\n"
            "# rathole 服务端（公网服务器上跑）\n"
            "[server]\n"
            "bind_addr = \"0.0.0.0:2333\"\n"
            "\n"
            "[server.services.ssh]\n"
            "bind_addr = \"0.0.0.0:6022\"\n"
            "EOF".format(ctx.destdir))
    ctx.run("cp -a README.md LICENSE "
            "{}/usr/share/doc/rathole/".format(ctx.destdir))
