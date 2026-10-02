"""audio —— 音频栈元包


许可证：Meta
"""

name = "audio"
version = "1.0.0"
release = 1
summary = "音频栈元包"
homepage = ""
license = "Meta"

# 远程源码的 sha256 尚未填回，构建前会被拒绝：
# 静默接受未校验的远程源码等于给供应链攻击敞开大门。
# 在能联网的构建机上执行：qybuild --fetch-checksums audio
source = ["https://example.org/src/audio-1.0.0.tar.xz"]
sha256 = []
checksum_pending = True

depends = ["alsa-lib", "alsa-utils", "pipewire", "libsndfile"]
makedepends = ["alsa-lib", "alsa-utils", "pipewire", "libsndfile"]
provides = []

requires_build_machine = True

network = False
compression = "gz"


def build(ctx):
    ctx.run("true")


def package(ctx):
    ctx.run("mkdir -p {}/usr/share/qiyuan".format(ctx.destdir))
