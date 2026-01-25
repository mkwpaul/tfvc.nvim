local M = {}
local function toggle_diff() require('tfvc').toggle_diff() end

M.mappings = {
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

if not vim.g.tf_disable_default_keymaps then
  for _, mapping in pairs(M.mappings) do
    vim.keymap.set('n', mapping.key, mapping.cmd, { desc = 'TFVC: ' .. mapping.desc })
  end
end

return M
