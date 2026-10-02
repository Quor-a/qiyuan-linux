#!/usr/bin/env python3
"""把 filesystem 配方的版本号改成指定值。"""
import pathlib
import sys

want = sys.argv[1]
p = pathlib.Path("recipes/filesystem.py")
t = p.read_text()
for old in ("0.1.0", "0.2.0", "0.3.0"):
    t = t.replace('version = "' + old + '"', 'version = "' + want + '"')
p.write_text(t)
