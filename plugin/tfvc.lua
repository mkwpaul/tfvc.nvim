local cmd_name = 'TF'

---@param opts vim.api.keyset.create_user_command.command_args
local function TF(opts)
  local tfvc = require 'tfvc'
  local fargs = opts.fargs
  local cmd = fargs[1]
  local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
  local subcommand = tfvc.commands[cmd]
  if subcommand then
    assert(type(subcommand.run) == 'function')
    opts.fargs = args
    subcommand.run(opts)
  else
    vim.notify(cmd_name .. ': Unknown subcommand: ' .. cmd, vim.log.levels.ERROR, { title = 'tfvc.nvim' })
  end
end

local function path_complete(start)
  if start == '' or start == '.' then
    start = './'
  end
  local entries = {}
  for current, type in vim.fs.dir(start) do
    if type == 'file' then
      table.insert(entries, start .. current)
    end
    if type == 'directory' then
      table.insert(entries, start .. current .. '/' )
    end
  end
  -- sort so directories are listed first, and then files
  table.sort(entries, function(a, b)
    local a_dir = a:sub(#a) == '/'
    local b_dir = b:sub(#b) == '/'
    if a_dir and not b_dir then return true end
    if b_dir and not a_dir then return false end
    return a > b
  end)
  return entries
end

local function TF_complete(arg_lead, cmdline, cursor_pos)
  local tfvc = require 'tfvc'
  local cmds = tfvc.commands
  local all_commands = vim.tbl_keys(cmds)
  -- check if we already have a subcommand typed, and do subcommand specific completion
  local subcmd, subcmd_arg_lead = cmdline:match('^' .. cmd_name .. '[!]*%s(%S+)%s(.*)$')
  if subcmd and subcmd_arg_lead and cmds[subcmd] then
    local subcomplete = cmds[subcmd].complete
    if subcomplete == true then
      return path_complete(subcmd_arg_lead)
    end
    if type(subcomplete) == 'function' then
      return subcomplete(subcmd_arg_lead, arg_lead, cmdline, cursor_pos)
    end
  end
  -- complete subcommands
  if cmdline:match('^' .. cmd_name .. '[!]*%s+%w*$') then
    return vim.tbl_filter(function(command)
      return command:find(arg_lead) ~= nil
    end, all_commands)
  end
end

vim.api.nvim_create_user_command(cmd_name, TF, {
  nargs = '+', bang = true, range = true,
  desc = 'Interacts with TF Version Control',
  complete = TF_complete,
})

local augroup_tfvc = vim.api.nvim_create_augroup('tfvc', { clear = true })
vim.api.nvim_create_autocmd('BufReadCmd', {
  group = augroup_tfvc, pattern = 'tfvc:///history/*',
  callback = function (args)
    require('tfvc.buftypes').history_callback(args)
  end
})

vim.api.nvim_create_autocmd('BufReadCmd', {
  group = augroup_tfvc, pattern = 'tfvc:///changeset/*',
  callback = function (args)
    require('tfvc.buftypes').changeset_callback(args)
  end
})

vim.api.nvim_create_autocmd('BufReadCmd', {
  group = augroup_tfvc, pattern = 'tfvc:///files/*',
  callback = function (args)
    require('tfvc.buftypes').files_callback(args)
  end
})

require 'tfvc.default_keymaps'
