# 编辑器支持

| 编辑器 | 文件 | 装法 |
|---|---|---|
| Vim / Neovim | `mo.vim` | 拷到 `~/.vim/syntax/`，`~/.vimrc` 加 `autocmd BufRead,BufNewFile *.mo set filetype=mo` |
| VS Code | `mo.tmLanguage.json` | 放进扩展的 `syntaxes/` 并在 `package.json` 里注册 `source.mo` |
| Emacs | — | 未做（缺 `mo-mode.el`） |
| LSP | — | **未做**。LSP 需要语义级能力（跳转定义、悬停类型），
而墨语言目前只生成行号级调试信息，没有变量与类型信息 |

IDE 支持目前只有**语法高亮**，没有补全、跳转、报错内联。
要做到后者需要 LSP 服务，而 LSP 需要编译器暴露符号位置与类型——
这在 1.x 里排在寄存器分配之后。
