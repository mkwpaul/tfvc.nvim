local function TF(...) return require ('tfvc').cmd_TF(...) end
local function TF_complete(...) return require('tfvc').cmd_TF_complete(...) end
local TF_opts = {
  nargs = '+',
  bang = true,
  range = true,
  desc = 'Interacts with TF Version Control',
  complete = TF_complete,
}

vim.api.nvim_create_user_command('TF', TF, TF_opts)

local augroup_tfvc = vim.api.nvim_create_augroup('tfvc', { clear = true })
vim.api.nvim_create_autocmd('BufReadCmd', {
  group = augroup_tfvc,
  pattern = 'tfvc:///history/*',
  callback = function (args) require('tfvc.buftypes').history_bufreadcmd(args) end
})

vim.api.nvim_create_autocmd('BufReadCmd', {
  group = augroup_tfvc,
  pattern = 'tfvc:///changeset/*',
  callback = function (args) require('tfvc.buftypes').changeset_bufreadcmd(args) end
})

vim.api.nvim_create_autocmd('BufReadCmd', {
  group = augroup_tfvc,
  pattern = 'tfvc:///files/*',
  callback = function (args) require('tfvc.buftypes').files_bufreadcmd(args) end
})

require 'tfvc.default_keymaps'
