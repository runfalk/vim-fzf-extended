" File:        fzf-extended.vim
" Maintainer:  Andreas Runfalk <andreas@runfalk.se>
" Description: Additional FZF helpers
" Last Change: 2018-02-23
" License:     MIT
" Bail quickly if the plugin was loaded, disabled or compatible is set

if (exists("g:loaded_fzfe") && g:loaded_fzfe) || &cp
    " finish
endif
let g:loaded_fzfe = 1

" Check that fzf is loaded
if exists("*fzf#run") == 0
    finish
endif


" List of files to ignore
let g:fzfe_ignore = [
\   "*.py[co]",
\   "*.swp",
\   ".DS_Store",
\   ".git",
\   "node_modules",
\]


" Make FZF respect current theme
let g:fzf_colors = {
\   "fg":      ["fg", "Normal"],
\   "bg":      ["bg", "Normal"],
\   "hl":      ["fg", "Comment"],
\   "fg+":     ["fg", "CursorLine", "CursorColumn", "Normal"],
\   "bg+":     ["bg", "CursorLine", "CursorColumn"],
\   "hl+":     ["fg", "Statement"],
\   "info":    ["fg", "PreProc"],
\   "border":  ["fg", "Ignore"],
\   "prompt":  ["fg", "Conditional"],
\   "pointer": ["fg", "Exception"],
\   "marker":  ["fg", "Keyword"],
\   "spinner": ["fg", "Label"],
\   "header":  ["fg", "Comment"],
\}



function! s:AnsiColor(string, highlight_name)
    let highlight_id = hlID(a:highlight_name)
    if highlight_id == 0
        return a:string
    endif

    " TODO: Add 16 color and true color support
    " TODO: Add bold and underline support

    let syn_id = synIDtrans(highlight_id)
    let fgcolor = synIDattr(syn_id, "fg")
    let bgcolor = synIDattr(syn_id, "bg")

    let prefix = ""
    if fgcolor != ""
        let prefix = "\033[38;5;" . fgcolor . "m"
    elseif bgcolor != ""
        let prefix = "\033[48;5;" . bgcolor . "m"
    endif

    return join([prefix, a:string, "\033[0m"], "")
endfunction


function! s:LeftPad(string, length, pad)
    let output = a:string
    while len(output) < a:length
        let output = a:pad . output
    endwhile
    return output
endfunction


function! s:ShellEscape(args)
    let parts = []
    for part in a:args
        let escaped_part = substitute(part, "'", "'\"'\"'", "g")
        call add(parts, "'" . escaped_part . "'")
    endfor
    return join(parts, " ")
endfunction


" Hold functions that format definition choices
let s:language_processors = {}

function! s:ProcessCtagsPython(ctags)
    let output = []
    for ctag in a:ctags
        let prefix = ""
        if ctag.type == "c"
            let prefix = s:AnsiColor("class", "pythonStatement")
        elseif ctag.type == "m"
            let prefix = "    " . s:AnsiColor("def", "pythonStatement")
        elseif ctag.type == "f"
            let prefix = s:AnsiColor("def", "pythonStatement")
        else
            continue
        endif
        let colored_name = s:AnsiColor(ctag.name, "pythonFunction")
        call add(output, join([prefix, colored_name, ctag.line], "\t"))
    endfor
    return output
endfunction
let s:language_processors.python = function("s:ProcessCtagsPython")


function! s:ProcessCtagsVimScript(ctags)
    let output = []
    for ctag in a:ctags
        let prefix = ""
        if ctag.type == "f"
            let prefix = s:AnsiColor("function", "vimCommand")
        elseif ctag.type == "c"
            let prefix = s:AnsiColor("command", "vimCommand")
        else
            continue
        endif

        " If function name starts with scoping, we need to highlight that
        let name_prefix = ""
        let function_name = ctag.name
        if function_name =~ "^[^:]:"
            let name_prefix = s:AnsiColor(function_name[0], "vimCommand")
            let function_name = function_name[1:]
        endif
        let colored_name = name_prefix . s:AnsiColor(function_name, "vimFunction")
        call add(output, join([prefix, colored_name, ctag.line], "\t"))
    endfor
    return output
endfunction
let s:language_processors.vim = function("s:ProcessCtagsVimScript")


function! s:ProcessCtags(ctags, filetype)
    if !has_key(s:language_processors, a:filetype)
        return []
    endif
    return s:language_processors[a:filetype](a:ctags)
endfunction


function! s:BufferGetCtags()
    let current_file = expand("%")

    " If the current buffer doesn't have a filename ctags can't be run
    if current_file == ""
        return []
    endif

    let output = []
    let cmd = s:ShellEscape(["ctags", "--sort=no", "-f", "-", current_file])
    for ctag in systemlist(cmd)
        let [name, _, regex, type; extra] = split(ctag, "\t")
        let line = regex[2:-5]
        call add(output, {"name": name, "type": type, "line": line})
    endfor
    return output
endfunction


function! s:GotoDefinition(selection)
    let [_, _, line] = split(a:selection, "\t")
    execute "/\\V\\^" . line . "\\$/"
    normal! zz
endfunction


function! s:GotoBuffer(selection)
    let [buffer_id, buffer_name] = split(a:selection, "\t")
    execute "buffer " . buffer_id
endfunction


function! s:FzfDefinitions()
    let fzf_opts = [
    \   "--with-nth=1,2",
    \   "--nth=2",
    \   "--tabstop=1",
    \   "--no-sort",
    \   "--tac",
    \   "--delimiter=\t",
    \   "--ansi",
    \]
    let fzf_source = s:ProcessCtags(s:BufferGetCtags(), &filetype)
    let fzf_args = fzf#wrap({
    \   "source": fzf_source,
    \   "options": fzf_opts,
    \   "sink": function("s:GotoDefinition"),
    \})
    call fzf#run(fzf_args)
endfunction


function! s:FzfBuffers()
    " Get list of buffers
    let fzf_source = []
    let buffer_max_id = bufnr("$")
    for buffer_id in range(1, buffer_max_id)
        let buffer_name = bufname(buffer_id)
        if buffer_name == ""
            continue
        endif
        let padded_number = s:LeftPad(buffer_id, len(buffer_max_id), " ")
        let colored_number = s:AnsiColor(padded_number, "Comment")
        call add(fzf_source, join([colored_number, buffer_name], "\t"))
    endfor

    let fzf_opts = ["--tabstop=1", "--delimiter=\t", "--ansi"]
    let fzf_args = fzf#wrap({
    \   "source": fzf_source,
    \   "options": fzf_opts,
    \   "sink": function("s:GotoBuffer")
    \})
    call fzf#run(fzf_args)
endfunction


function! s:FzfFilesIngore(ignore_list)
    let source_cmd = ["find", ".", "-not", "("]
    for ignore in a:ignore_list
        call extend(source_cmd, ["-name", ignore, "-prune"])
    endfor
    call extend(source_cmd, [")", "-type", "f", "-print"])

    let fzf_args = fzf#wrap({
    \   "source": s:ShellEscape(source_cmd) . " 2> /dev/null | cut -c3-",
    \   "options": ["--multi"],
    \})
    echo source_cmd
    echo s:ShellEscape(source_cmd) . " 2> /dev/null"
    call fzf#run(fzf_args)
endfunction


" We need Ctags to provide definition search
if executable("ctags")
    command! FZFDefinitions call s:FzfDefinitions()
else
    command! FZFDefinitions echo "ctags not found in path"
endif

command! FZFBuffers call s:FzfBuffers()
command! FZFFiles call s:FzfFilesIngore(g:fzfe_ignore)
