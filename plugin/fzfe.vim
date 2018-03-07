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


let s:filetype_ctag_overrides = {
\   "cpp": "C++",
\}


function! s:ansi_color(string, highlight_name)
    let highlight_id = hlID(a:highlight_name)
    if highlight_id == 0
        return a:string
    endif

    " TODO: Add 16 color and true color support

    let syn_id = synIDtrans(highlight_id)
    let fgcolor = synIDattr(syn_id, "fg")
    let bgcolor = synIDattr(syn_id, "bg")
    let bold = synIDattr(syn_id, "bold") == "1"
    let underline = synIDattr(syn_id, "underline") == "1"
    let undercurl = synIDattr(syn_id, "undercurl") == "1"

    let prefix = ""
    if fgcolor != ""
        let prefix = prefix . "\033[38;5;" . fgcolor . "m"
    endif
    if bgcolor != ""
        let prefix = prefix . "\033[48;5;" . bgcolor . "m"
    endif
    if bold
        let prefix = prefix . "\033[1m"
    endif
    if underline || undercurl
        let prefix = prefix . "\033[4m"
    endif

    return join([prefix, a:string, "\033[0m"], "")
endfunction


function! s:temp_save_buffer()
    let filename = tempname()
    execute "silent %w !cat - > " . filename
    return filename
endfunction


function! s:left_pad(string, length, pad)
    let output = a:string
    while len(output) < a:length
        let output = a:pad . output
    endwhile
    return output
endfunction


function! s:shell_escape(args)
    return join(map(a:args, {k, v -> shellescape(v)}), " ")
endfunction


" Hold functions that format definition choices
let s:language_processors = {}


function! s:process_ctags_python(ctags)
    let output = []
    for ctag in a:ctags
        let prefix = ""
        if ctag.type == "c"
            let prefix = s:ansi_color("class", "pythonStatement")
        elseif ctag.type == "m"
            let prefix = "    " . s:ansi_color("def", "pythonStatement")
        elseif ctag.type == "f"
            let prefix = s:ansi_color("def", "pythonStatement")
        else
            continue
        endif
        let colored_name = s:ansi_color(ctag.name, "pythonFunction")
        call add(output, join([prefix, colored_name, ctag.line], "\t"))
    endfor
    return output
endfunction
let s:language_processors.python = function("s:process_ctags_python")


function! s:process_ctags_vim(ctags)
    let output = []
    for ctag in a:ctags
        let prefix = ""
        if ctag.type == "f"
            let prefix = s:ansi_color("function", "vimCommand")
        elseif ctag.type == "c"
            let prefix = s:ansi_color("command", "vimCommand")
        else
            continue
        endif

        " If function name starts with scoping, we need to highlight that
        let name_prefix = ""
        let function_name = ctag.name
        if function_name =~ "^[^:]:"
            let name_prefix = s:ansi_color(function_name[0], "vimCommand")
            let function_name = function_name[1:]
        endif
        let colored_name = name_prefix . s:ansi_color(function_name, "vimFunction")
        call add(output, join([prefix, colored_name, ctag.line], "\t"))
    endfor
    return output
endfunction
let s:language_processors.vim = function("s:process_ctags_vim")


let s:c_builtins = [
\   "void",
\   "bool",
\   "short",
\   "short int",
\   "signed short",
\   "signed short int",
\   "unsigned short",
\   "unsigned short int",
\   "int",
\   "signed",
\   "signed int",
\   "unsigned",
\   "unsigned int",
\   "long",
\   "long int",
\   "signed long",
\   "signed long int",
\   "unsigned long",
\   "unsigned long int",
\   "long long",
\   "long long int",
\   "signed long long",
\   "signed long long int",
\   "unsigned long long",
\   "unsigned long long int",
\   "unsigned long long int",
\   "float",
\   "double",
\   "long double",
\]

function! s:process_ctags_cpp(ctags)
    let output = []
    for ctag in a:ctags
        let belongs_to = get(ctag.metadata, "class", "")
        let return_type = get(ctag.metadata, "typeref", "")[9:] " Strip typename:

        let prefix = ""
        let name = ctag.name
        if ctag.type == "f"
            let prefix = return_type
            if prefix == "" && belongs_to == name
                let prefix = s:ansi_color("(constructor)", "cCommentL")
            elseif index(s:c_builtins, return_type) != -1
                let prefix = s:ansi_color(return_type, "cType")
            endif

            if belongs_to != ""
                let generic_match = matchstr(ctag.content, belongs_to . "<[^>]>")
                if generic_match != ""
                    let belongs_to = generic_match
                endif
                let name = belongs_to . "::" . s:ansi_color(name, "cCustomFunc")
            endif

            let name = name . ctag.signature
        elseif ctag.type == "c"
            let prefix = s:ansi_color("class", "cppStructure")
            if belongs_to != ""
                let generic_match = matchstr(ctag.content, belongs_to . "<[^>]>")
                if generic_match != ""
                    let name = generic_match
                endif
            endif
        elseif ctag.type == "g"
            if ctag.content =~? "enum\\s\\+class"
                let prefix = s:ansi_color("enum class", "cStructure")
            else
                let prefix = s:ansi_color("enum", "cStructure")
            endif
        elseif ctag.type == "s"
            let prefix = s:ansi_color("struct", "cStructure")
        else
            continue
        endif
        call add(output, join([prefix, name, ctag.line], "\t"))
    endfor
    return output
endfunction
let s:language_processors.cpp = function("s:process_ctags_cpp")


function! s:process_ctags_default(ctags)
    let output = []
    for ctag in a:ctags
        if index(["f", "m", "c"], ctag.type) != -1
            call add(output, join([
            \   "",
            \   substitute(ctag.content, "^\\s*\\(.\\{-}\\)\\s*$", "\\1", ""),
            \   ctag.line,
            \], "\t"))
        endif
    endfor
    return output
endfunction


function! s:process_ctags(ctags, filetype)
    if !has_key(s:language_processors, a:filetype)
        return s:process_ctags_default(a:ctags)
    endif
    return s:language_processors[a:filetype](a:ctags)
endfunction


function! fzfe#buffer_ctags()
    " If the current buffer doesn't have a filetype ctags can't be run
    if &filetype == ""
        return []
    endif

    let output = []
    let ctag_language = &filetype
    if has_key(s:filetype_ctag_overrides, &filetype)
        let ctag_language = s:filetype_ctag_overrides[&filetype]
    endif

    let temp_file = s:temp_save_buffer()
    let cmd = s:shell_escape([
    \   "ctags",
    \   "--excmd=pattern",
    \   "--fields=+aneS",
    \   "--language-force=" . ctag_language,
    \   "--sort=no",
    \   "-f", "-",
    \   temp_file,
    \])

    for ctag in systemlist(cmd)
        let [name, _, regex, type; extra] = split(ctag, "\t")

        let metadata = {}
        for ext in extra
            let [key; other] = split(ext, ":")
            let value = join(other, ":")
            let metadata[key] = value
        endfor

        let content = regex[2:-5]
        call add(output, {
        \   "access": get(metadata, "access", ""),
        \   "content": content,
        \   "line": metadata.line,
        \   "line_end": get(metadata, "end", metadata.line),
        \   "name": name,
        \   "signature": get(metadata, "signature", ""),
        \   "type": type,
        \   "metadata": metadata,
        \})
    endfor

    " Remove temp file to avoid cluttering
    call delete(temp_file)

    return output
endfunction


function! fzfe#goto_line(line)
    execute ":" . a:line
    normal! zz
endfunction


function! fzfe#open_buffer(buffer_id, method)
    if a:method == "replace"
        execute "buffer " . a:buffer_id
    elseif a:method == "split"
        execute "sbuffer " . a:buffer_id
    elseif a:method == "vsplit"
        execute "vert sbuffer " . a:buffer_id
    else
        echoerr printf("Invalid method '%s'", a:method)
    endif
endfunction

function! fzfe#fzf_definitions()
    let fzf_opts = [
    \   "--with-nth=1,2",
    \   "--nth=2",
    \   "--tabstop=1",
    \   "--no-sort",
    \   "--tac",
    \   "--delimiter=\t",
    \   "--ansi",
    \]
    let fzf_source = s:process_ctags(fzfe#buffer_ctags(), &filetype)
    let fzf_args = fzf#wrap({
    \   "source": fzf_source,
    \   "options": fzf_opts,
    \   "sink": function("s:fzf_definitions_cb"),
    \})
    call fzf#run(fzf_args)
endfunction

function! s:fzf_definitions_cb(selection)
    let [_, _, line] = split(a:selection, "\t")
    call fzfe#goto_line(line)
endfunction


function! fzfe#fzf_buffers()
    " Get list of buffers
    let fzf_source = []
    let buffer_max_id = bufnr("$")
    for buffer_id in range(1, buffer_max_id)
        let buffer_name = bufname(buffer_id)
        if buffer_name == ""
            continue
        endif
        let padded_number = s:left_pad(buffer_id, len(buffer_max_id), " ")
        let colored_number = s:ansi_color(padded_number, "Comment")
        call add(fzf_source, join([colored_number, buffer_name], "\t"))
    endfor

    let fzf_opts = [
    \   "--ansi",
    \   "--delimiter=\t",
    \   "--expect=ctrl-v,ctrl-s,ctrl-w",
    \   "--multi",
    \   "--tabstop=1",
    \]
    let fzf_args = fzf#wrap({
    \   "source": fzf_source,
    \   "options": fzf_opts,
    \   "sink*": function("s:fzf_buffers_cb")
    \})
    call fzf#run(fzf_args)
endfunction

function! s:fzf_buffers_cb(selection)
    let [key; buffer_list] = a:selection
    let action = {
    \   "": "replace",
    \   "ctrl-s": "split",
    \   "ctrl-v": "vsplit",
    \   "ctrl-w": "wipe",
    \}[key]
    for line in buffer_list
        let [buffer_id, buffer_name] = split(line, "\t")
        if action == "wipe"
            execute "bwipeout" . buffer_id
        else
            call fzfe#open_buffer(buffer_id, action)
        endif
    endfor
endfunction


function! fzfe#fzf_files_ignore(ignore_list, ...)
    let path = simplify(fnamemodify(get(a:000, 0, "."), ":p"))
    let simplified_path = fnamemodify(path, ":~")

    let source_cmd = ["find", ".", "-not", "("]
    for ignore in a:ignore_list
        if source_cmd[-1] != "("
            call add(source_cmd, "-o")
        endif
        call extend(source_cmd, ["-name", ignore, "-prune"])
    endfor
    call extend(source_cmd, [")", "-type", "f", "-print"])

    let fzf_source = printf(
    \    "%s 2> /dev/null | cut -c3-",
    \    s:shell_escape(source_cmd),
    \)
    let fzf_args = fzf#wrap({
    \   "source": fzf_source,
    \   "dir": path,
    \   "options": ["--multi", "--prompt=" . simplified_path],
    \})
    call fzf#run(fzf_args)
endfunction


" We need Ctags to provide definition search
if executable("ctags")
    command! FZFDefinitions call fzfe#fzf_definitions()
else
    command! FZFDefinitions echo "ctags not found in path"
endif

command! FZFBuffers call fzfe#fzf_buffers()
command! -nargs=? -complete=dir FZFFiles
\   call fzfe#fzf_files_ignore(g:fzfe_ignore, <f-args>)
