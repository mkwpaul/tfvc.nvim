
---@param args vim.api.keyset.create_user_command.command_args
local function diff_against(args)
  local diff = require 'unified_diff'
  local buf = vim.api.nvim_get_current_buf()
  diff.setup_unified_diff(buf, args.fargs[1])
end

local function stop_diff()
  local diff = require 'unified_diff'
  local buf = vim.api.nvim_get_current_buf()
  diff.stop_unified(buf)
end

vim.api.nvim_create_user_command('UDiff', diff_against, { nargs = 1, complete = 'file' })
vim.api.nvim_create_user_command('UDiffStop', stop_diff, { nargs = 0 })
