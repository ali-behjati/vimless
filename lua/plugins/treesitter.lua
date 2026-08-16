return function(config)
    if type(config.plugins.treesitter) == 'boolean' and not config.plugins.treesitter then
        return {}
    end

    -- Parsers to keep installed. On `main` a parser and its queries are
    -- installed together into `stdpath('data')/site`, so this list is the whole
    -- story -- there is no separate set of queries to keep in sync. Parsers
    -- pulled in as dependencies (ecma, jsx, html_tags) install themselves.
    --
    -- Markdown fences inject whichever language the info string names, so this
    -- list doubles as the set of languages that highlight inside ``` blocks.
    local ensure_installed = {
        -- editing Neovim itself
        'lua', 'luadoc', 'vim', 'vimdoc', 'query',

        -- languages configured elsewhere in this config
        'rust', 'python', 'go', 'haskell', 'zig', 'nix', 'clojure', 'c',
        'javascript', 'typescript', 'tsx',

        -- markup, config and data
        'markdown', 'markdown_inline', 'html', 'css', 'json', 'yaml', 'toml',
        'bash', 'make', 'dockerfile', 'regex', 'diff',

        -- git
        'gitcommit', 'git_rebase', 'git_config', 'gitattributes', 'gitignore',
    }

    -- ------------------------------------------------------------------
    -- Incremental selection
    --
    -- `main` dropped the `incremental_selection` module and core Neovim has no
    -- replacement, so the gnn/./;/, bindings are rebuilt here on the core
    -- treesitter API. Each buffer keeps a stack of the nodes it expanded
    -- through, which is what lets `,` walk back down again.
    -- ------------------------------------------------------------------
    local stacks = {}
    local increment, decrement

    local function node_range(node)
        local srow, scol, erow, ecol = node:range()
        return { srow, scol, erow, ecol }
    end

    local function select_node(bufnr, node)
        local srow, scol, erow, ecol = node:range()

        -- Treesitter end columns are exclusive, so a node ending at column 0
        -- actually ends at the end of the previous line.
        if ecol == 0 and erow > srow then
            erow = erow - 1
            ecol = #(vim.api.nvim_buf_get_lines(bufnr, erow, erow + 1, false)[1] or '')
        end

        vim.fn.setpos("'<", { bufnr, srow + 1, scol + 1, 0 })
        vim.fn.setpos("'>", { bufnr, erow + 1, math.max(ecol, 1), 0 })
        vim.cmd 'normal! gv'
    end

    -- `.`, `;` and `,` are only bound while a selection is actually being
    -- expanded, and buffer-locally at that. flash.nvim's char module owns `;`
    -- and `,` globally (repeat f/t), so binding them globally here would break
    -- it -- and lose, since flash maps them after this plugin loads.
    local armed = {}

    local function disarm(bufnr)
        for _, lhs in ipairs { '.', ';', ',' } do
            pcall(vim.keymap.del, 'x', lhs, { buffer = bufnr })
        end

        if armed[bufnr] then
            pcall(vim.api.nvim_del_autocmd, armed[bufnr])
            armed[bufnr] = nil
        end
        stacks[bufnr] = nil
    end

    local function init_selection()
        local bufnr = vim.api.nvim_get_current_buf()

        local ok, node = pcall(vim.treesitter.get_node)
        if not ok or not node then
            return
        end

        stacks[bufnr] = { node }
        select_node(bufnr, node)

        if armed[bufnr] then
            return
        end

        vim.keymap.set('x', '.', function() increment(false) end,
            { buffer = bufnr, desc = 'Treesitter: expand to parent node' })
        vim.keymap.set('x', ';', function() increment(true) end,
            { buffer = bufnr, desc = 'Treesitter: expand to enclosing scope' })
        vim.keymap.set('x', ',', decrement,
            { buffer = bufnr, desc = 'Treesitter: shrink selection' })

        -- Dropping out of visual mode ends the selection. Deferred because
        -- `normal! gv` itself dips through normal mode on the way back in.
        armed[bufnr] = vim.api.nvim_create_autocmd('ModeChanged', {
            pattern  = '*:*',
            callback = function()
                vim.schedule(function()
                    if not vim.fn.mode():match('^[vV\22]') then
                        disarm(bufnr)
                    end
                end)
            end,
        })
    end

    -- Node ids captured as `@local.scope` by the language's `locals` query.
    -- Returns nil when the language ships no `locals` query at all, which is
    -- the signal to fall back to plain node expansion.
    local function scopes(bufnr)
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
        if not ok or not parser then
            return nil
        end

        local query = vim.treesitter.query.get(parser:lang(), 'locals')
        if not query then
            return nil
        end

        local found = {}
        for id, node in query:iter_captures(parser:parse(true)[1]:root(), bufnr, 0, -1) do
            if query.captures[id] == 'local.scope' then
                found[node:id()] = true
            end
        end
        return found
    end

    -- Walk up until the range actually grows; ancestors covering exactly the
    -- same text would otherwise make the keymap look like it did nothing.
    local function grow(node, accept)
        local parent = node:parent()

        while parent do
            if not vim.deep_equal(node_range(parent), node_range(node))
                and (not accept or accept(parent)) then
                return parent
            end
            parent = parent:parent()
        end
    end

    function increment(scope)
        local bufnr = vim.api.nvim_get_current_buf()
        local stack = stacks[bufnr]

        if not stack or #stack == 0 then
            return init_selection()
        end

        local accept
        if scope then
            local in_scope = scopes(bufnr)
            accept = in_scope and function(node) return in_scope[node:id()] end or nil
        end

        local next_node = grow(stack[#stack], accept)
        if not next_node then
            return select_node(bufnr, stack[#stack])
        end

        stack[#stack + 1] = next_node
        select_node(bufnr, next_node)
    end

    function decrement()
        local bufnr = vim.api.nvim_get_current_buf()
        local stack = stacks[bufnr]

        if not stack or #stack == 0 then
            return
        end

        if #stack > 1 then
            stack[#stack] = nil
        end
        select_node(bufnr, stack[#stack])
    end

    return {
        'nvim-treesitter/nvim-treesitter',
        branch       = 'main',
        build        = ':TSUpdate',
        priority     = 800,
        lazy         = false, -- `main` explicitly does not support lazy-loading
        dependencies = {
            -- Pulled in only for its `queries/<lang>/textobjects.scm`, which is
            -- what mini.ai's `gen_spec.treesitter` reads. Its own select/move/
            -- swap mappings are left unconfigured, exactly as they were on
            -- `master`.
            { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
        },
        config = function()
            if config.plugins.treesitter and type(config.plugins.treesitter) == 'function' then
                config.plugins.treesitter()
                return
            end

            local wanted = ensure_installed
            if config.plugins.treesitter and type(config.plugins.treesitter) == 'table' then
                wanted = config.plugins.treesitter.ensure_installed or wanted
            end

            require 'nvim-treesitter'.setup {}
            require 'nvim-treesitter'.install(wanted)

            -- Highlighting is core's job on `main`, and core only starts it
            -- when asked. Guarded so a filetype with no installed parser
            -- quietly keeps its regex syntax instead of erroring.
            local function start(bufnr)
                pcall(vim.treesitter.start, bufnr)
            end

            vim.api.nvim_create_autocmd('FileType', {
                group    = vim.api.nvim_create_augroup('user_treesitter', { clear = true }),
                callback = function(ev) start(ev.buf) end,
            })

            -- Any buffer already loaded by the time this runs missed the
            -- autocmd above.
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(bufnr) then
                    start(bufnr)
                end
            end

            -- Only the entry point is global; see init_selection above.
            vim.keymap.set('n', 'gnn', init_selection,
                { desc = 'Treesitter: init selection' })
        end
    }
end
