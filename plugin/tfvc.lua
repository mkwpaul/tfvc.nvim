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

-- default_keymaps
if not vim.g.tfvc_disable_default_keymaps then
  local function toggle_diff() require('tfvc.utils').toggle_diff() end
  local mappings = {
    { key = '<leader>ta', cmd = '<cmd>TF add<CR>', desc = 'Add current File to Source Control', },
    { key = '<leader>tu', cmd = '<cmd>TF undo<CR>', desc = 'Undo changes in current file', },
    { key = '<leader>ti', cmd = '<cmd>TF info<CR>', desc = 'Show info about current file', },
    { key = '<leader>tc', cmd = '<cmd>TF checkout<CR>', desc = 'Checkout file for editing', },
    { key = '<leader>tl', cmd = '<cmd>TF diff<CR>', desc = 'Compare local file to latest server version', },
    { key = '<leader>tw', cmd = '<cmd>TF openWebHistory<CR>', desc = 'Open Web History for current File/Directory', },
    { key = '<leader>ts', cmd = '<cmd>TF status<CR>', desc = 'Load Status (Pending Changes) into quickfix list', },
    { key = '<leader>tr', cmd = '<cmd>TF rename<CR>', desc = 'Renames/Moves file or directory', },
    { key = '<leader>th', cmd = '<cmd>TF history<CR>', desc = 'Shows history of current file in interactive buffer', },
    { key = '<C-A-j>', cmd =  '<cmd>cnext<CR><cmd>TF diff<CR><CR>', desc = 'Diff next file in quickfix list' },
    { key = '<C-A-k>', cmd =  '<cmd>cprev<CR><cmd>TF diff<CR><CR>', desc = 'Diff previous file in quickfix list' },
    { key = '<C-A-l>', cmd =  toggle_diff , desc = 'Toggle diff view' },
  }

  for _, mapping in pairs(mappings) do
    vim.keymap.set('n', mapping.key, mapping.cmd, { desc = 'TFVC: ' .. mapping.desc })
  end
end
