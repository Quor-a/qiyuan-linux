" 墨语言 (Mo) — Vim / Neovim 语法高亮
" 安装: cp mo.vim ~/.vim/syntax/ 并在 ~/.vimrc 加 autocmd BufRead *.mo setf mo
if exists("b:current_syntax")
  finish
endif

syn keyword moKeyword   fn return let var struct import if else while break continue
syn keyword moType      i64 byte ptr
syn keyword moBuiltin   load8 load64 store8 store64 syscall argc argv
syn keyword moTodo      TODO FIXME XXX NOTE

syn match   moComment   "#.*$" contains=moTodo
syn match   moNumber    "\<\d\+\>"
syn match   moChar      "'[^']*'"
syn region  moString    start=+"+ skip=+\\\\\\|\\"+ end=+"+
syn match   moOperator  "[-+*/%=!<>&|^~]\+"

hi def link moKeyword   Keyword
hi def link moType      Type
hi def link moBuiltin   Function
hi def link moComment   Comment
hi def link moTodo      Todo
hi def link moNumber    Number
hi def link moChar      Character
hi def link moString    String
hi def link moOperator  Operator

let b:current_syntax = "mo"
