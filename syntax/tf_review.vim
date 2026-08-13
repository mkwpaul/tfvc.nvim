" Syntax highlighting for TFVC Review buffer

" Comments and headers
syn match Comment "^#.*"
syn match Function "^##.*"

" Change type icons and status
syn keyword @diff.plus add
syn keyword @diff.delta edit
syn keyword @diff.minus delete
syn keyword Conditional merge branch
syn keyword Identifier rename encoding lock

" File entries - highlight the leading icon/marker
syn match Special "^  [^ ]\+ "

" Diff sections
syn match Delimiter "^---$"

" Include diff syntax for inline diff sections
runtime! syntax/diff.vim
