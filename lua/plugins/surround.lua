return function(config)
    if type(config.plugins.surround) == 'boolean' and not config.plugins.surround then
        return {}
    end

    return {
        "kylechui/nvim-surround",
        version = "^3.0.0",
        event = "VeryLazy",
        config = function()
            require("nvim-surround").setup({
                -- Configuration here, or leave empty to use defaults
            })
        end
    }
end

