local fn = vim.fn

-- Autocommand that reloads neovim whenever you save the plugins.lua file
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerSync
  augroup end
]])

-- Use a protected call so we don't error out on first use
local status_ok, packer = pcall(require, "packer")
if not status_ok then
	return
end
-- Have packer use a popup window
packer.init({
	display = {
		open_fn = function()
			return require("packer.util").float({ border = "rounded" })
		end,
	},
})

-- Install your plugins here
return packer.startup(function(use)
  use ("tpope/vim-fugitive")
  use { 'folke/tokyonight.nvim' }
  use { 'jose-elias-alvarez/null-ls.nvim',
  		config = [[require('config.null-ls')]],
  		requires = { 'nvim-lua/plenary.nvim' }}
  use { 'rhysd/open-pdf.vim' }
  use { 'Shougo/unite.vim' }
  use { 'neovim/nvim-lspconfig' }
  use { 'neoclide/coc.nvim', branch = 'release' }

	if PACKER_BOOTSTRAP then
		require("packer").sync()
	end
end)
