return function(config)
    if type(config.plugins.rust) == 'boolean' and not config.plugins.rust then
        return {}
    end

    -- Enable Rust.vim's automatic Rustfmt on save.
    vim.g.rustfmt_autosave = 1
    vim.g.rustfmt_command  = 'rustup run nightly rustfmt'

    -- Autocommand that overrides doc-comment colours with comment colours.
    vim.cmd [[
        augroup rust-comment-hl
        autocmd FileType rust hi link rustCommentLineDoc rustCommentLine
        augroup END
    ]]

    return {
        'mrcjkb/rustaceanvim',
        dependencies = {
            'nvim-lua/plenary.nvim' ,
            'SmiteshP/nvim-navic',
            'saecki/crates.nvim',
        },
        config   = function()
            if config.plugins.rust and type(config.plugins.rust) == 'function' then
                config.plugins.rust()
                return
            end

            local opts = {
                crates = {
                    text = {
                        loading    = "  Loading...",
                        version    = "  %s",
                        prerelease = "  %s",
                        yanked     = "  %s yanked",
                        nomatch    = "  Not found",
                        upgrade    = "  %s",
                        error      = "  Error fetching crate",
                    },
                    completion = {
                        text = {
                            prerelease = "  pre-release ",
                            yanked     = "  yanked ",
                        },
                    },
                },
            }

            local tools  = require 'rustaceanvim'
            local crates = require 'crates'

            vim.g.rustaceanvim = {
                server = {
                    on_attach = function(client, buffer)
                        require 'nvim-navic'.attach(
                            client,
                            buffer
                        )
                    end,
                    default_settings = {
                        ['rust-analyzer'] = {
                            check = {
                                command = 'clippy'
                            }
                        },
                    },
                },
            }

            crates.setup(opts.crates)

            local keymap = require 'keymap'

            keymap:registerLanguage('Rust',   'rust')
            keymap:registerLanguage('Crates', 'toml')

            _G.HydraMappings.Crates.Crates.u = { 'Update Crate',       crates.update_crate,                     { exit = true } }
            _G.HydraMappings.Crates.Crates.U = { 'Upgrade Crate',      crates.upgrade_crate,                    { exit = true } }
            _G.HydraMappings.Crates.Crates.i = { 'Crate Info',         crates.show_popup,                       { exit = true } }
            _G.HydraMappings.Crates.Crates.d = { 'Crate Dependencies', crates.show_dependencies_popup,          { exit = true } }
            _G.HydraMappings.Crates.Crates.f = { 'Crate Features',     crates.show_features_popup,              { exit = true } }
            _G.HydraMappings.Crates.Crates.v = { 'Crate Versions',     crates.show_versions_popup,              { exit = true } }
            _G.HydraMappings.Rust.Rust.k     = { 'Move Item Up',       function() vim.cmd.RustLsp { 'moveItem',  'up' } end,   { exit = true } }
            _G.HydraMappings.Rust.Rust.j     = { 'Move Item Down',     function() vim.cmd.RustLsp { 'moveItem',  'down' } end, { exit = true } }
            _G.HydraMappings.Rust.Rust.e     = { 'Expand Macro',       function() vim.cmd.RustLsp('expandMacro') end,          { exit = true } }
            _G.HydraMappings.Rust.Rust.s     = { 'Parent Module',      function() vim.cmd.RustLsp('parentModule') end,         { exit = true } }
            _G.HydraMappings.Rust.Rust.c     = { 'Open Cargo.toml',    function() vim.cmd.RustLsp('openCargo') end,            { exit = true } }
        end
    }
end
