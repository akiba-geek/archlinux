local null_ls = require("null-ls")

null_ls.setup({
    on_attach = function(client, bufnr)
        if client.supports_method("textDocument/formatting") then
            vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
            vim.api.nvim_create_autocmd("BufWritePre", {
                group = augroup,
                buffer = bufnr,
                callback = function()
                    vim.lsp.buf.format({ bufnr = bufnr })
                end,
            })
        end
    end,
    sources = {
        null_ls.builtins.diagnostics.mypy.with({
                command = "dmypy",
                args = function(params)
                            return {
                                "--status-file",
                                "/home/akibageek/git/internal-bs-core/bot/.dmypy.json",
                                "check",
                                params.temp_path,
                                params.bufname,
                            }
                        end,
                prefer_local = "/home/akibageek/virtualenv/internal-bs-core/bin",
                timeout = 50000,
                -- Do not run in fugitive windows, or when inside of a .venv area
                runtime_condition = function(params)
                    if string.find(params.bufname,"fugitive") or string.find(params.bufname,".venv") then
                        return false
                    else
                        return true
                    end
                end,
            }), 
        null_ls.builtins.diagnostics.flake8.with({
            extra_args = {"--ignore=E501,E302,W503,W504,E231,E203"},
            }),
        null_ls.builtins.formatting.black,
    },
})
