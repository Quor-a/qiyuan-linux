"""qydemo —— 演示应用配方。

依赖 libqydemo，用来验证：依赖求解 → 按序构建 → 构建依赖装进 sysroot →
包管理器按依赖安装。
"""

name = "qydemo"
version = "0.2.0"
release = 1
summary = "澜岫构建系统演示命令行工具"
description = "调用 libqydemo 打印版本与运算结果，用于端到端验证整套链路。"
homepage = "https://example.invalid/lanxiu"
license = "MIT"

source = ["tests/demo/qydemo"]
sha256 = []

# 运行时依赖：包管理器会先装它，再装本包
# 同上：glibc 依赖在自举完成后补上
depends = ["libqydemo"]
makedepends = ["libqydemo"]

network = False
compression = "gz"


def build(ctx):
    ctx.run("make PREFIX=/usr")


def package(ctx):
    ctx.run("make DESTDIR={} install".format(ctx.destdir))
