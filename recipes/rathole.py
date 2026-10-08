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
sha256 = []
checksum_pending = True

depends = []
makedepends = ["rust"]
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    ctx.log("Rust release 构建（--release + strip，产出单二进制）")
    ctx.run("cd rathole-0.5.0 && cargo build --release --workspace")
    ctx.run("strip rathole-0.5.0/target/release/rathole")
    ctx.run("rathole-0.5.0/target/release/rathole --help | head -3")


def package(ctx):
    ctx.run("mkdir -p {0}/usr/bin {0}/etc/rathole "
            "{0}/usr/share/doc/rathole".format(ctx.destdir))
    ctx.run("install -m755 rathole-0.5.0/target/release/rathole "
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
    ctx.run("cp -a rathole-0.5.0/README.md rathole-0.5.0/LICENSE "
            "{}/usr/share/doc/rathole/".format(ctx.destdir))
