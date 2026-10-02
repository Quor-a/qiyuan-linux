#!/usr/bin/env python3
"""把 filesystem 配方的版本号恢复为 0.1.0。

测试会临时改版本号来构造升级场景。中断后不恢复的话，
下一次运行的基线全错，症状是一堆莫名其妙的失败。
"""
import pathlib

p = pathlib.Path("recipes/filesystem.py")
t = p.read_text()
for old in ("0.2.0", "0.3.0"):
    t = t.replace('version = "' + old + '"', 'version = "' + '0.1.0' + '"')
p.write_text(t)
