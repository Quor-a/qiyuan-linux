"""audio —— 音频栈元包


许可证：Meta
"""

name = "audio"
version = "1.0.0"
release = 1
summary = "音频栈元包"
homepage = ""
license = "Meta"

source = []
sha256 = []

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
