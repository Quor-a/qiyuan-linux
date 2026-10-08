"""Go 工具链 —— frp / rathole 等自研网络工具的构建依赖

许可证：BSD-3-Clause（Go）
注意：这是构建机工具（requires_build_machine），不进目标系统镜像。
系统内穿透工具（frpc/frps）是 Go 静态二进制，构建完直接进包。
"""

name = "go"
version = "1.24.4"
release = 1
summary = "Go 编译工具链（仅构建机使用）"
license = "BSD-3-Clause"

source = ["https://mirrors.aliyun.com/golang/go1.24.4.linux-amd64.tar.gz"]
sha256 = ["77e5da33bb72aeaef1ba4418b6fe511bc4d041873cbf82e5aa6318740df98717"]
checksum_pending = False

depends = []
makedepends = []
provides = []

requires_build_machine = True
network = False
compression = "gz"


def build(ctx):
    # Go 官方 tarball 自带预编译工具链，解包即用；只需要做一次自检
    # （strip_components=1 后 go/ 顶层目录被剥掉，bin/go 直接在 src 下）
    ctx.log("Go 预编译工具链：解包 + go version 自检")
    ctx.run("./bin/go version")


def package(ctx):
    # 安装到 /usr/lib/go，可执行软链到 /usr/bin
    import os
    dest = os.path.join(str(ctx.destdir), "usr/lib/go")
    ctx.run("mkdir -p {}/usr/lib {}/usr/bin".format(ctx.destdir, ctx.destdir))
    ctx.run("cp -a . {}".format(dest))
    ctx.run("ln -sf /usr/lib/go/bin/go {}/usr/bin/go".format(ctx.destdir))
    ctx.run("ln -sf /usr/lib/go/bin/gofmt {}/usr/bin/gofmt".format(ctx.destdir))
