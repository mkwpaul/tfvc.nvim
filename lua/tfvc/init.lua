local M = {}

---@param args vim.api.keyset.create_user_command.command_args
local function get_path_from_cmd_args(args)
  local u = require 'tfvc.utils'
  local path = nil
  if #args.fargs > 0 then
    path = vim.fn.expand(args.fargs[1])
    local mapped, local_path = pcall(u.to_local_path, path, nil, 'history')
    if mapped then
      path = local_path
    end
  end
  if not path then
    path = u.get_local_path('history') or '.'
  end
  return path
end

local function cmd_from_verb(verb, print_stdout, callback)
  ---@param opts vim.api.keyset.create_user_command.command_args
  return function(opts)
    local args = { 'vc' , verb, get_path_from_cmd_args(opts) }
    require('tfvc.utils').tf_cmd(args, { print_stdout = print_stdout } , callback)
  end
end

---@class tfvc.subcommand
---@field desc string
---@field complete nil|boolean|function
---@field run fun(opts: vim.api.keyset.create_user_command.command_args)

--- Commands like checkout, delete or undo currently don't properly work with directories.
--- We would need to pass '/recursive' to TF.exe so that the whole directory can be acted on.
--- On the other hand, checking out, deleting or undoing entire directories could be pretty dangerous.
--- You would probably expect a confirmation prompt before doing that with directories,
--- especially if invoked via keymap.
--- Otherwise you could easily loose alot of progress accidentally.
--- This is probably not worth the hassle of implementation.
--- It's not something that needs to be done very often
--- and can be easily accomplished by just using the command line tool directly.

---@type table<string,tfvc.subcommand>
M.commands = {
  add = {
    desc = 'Add file to version sontrol',
    complete = true,
    run = cmd_from_verb('add', false),
  },
  undo = {
    desc = 'Undo changes in file. Deliberately does not work with directories.',
    complete = true,
    run = cmd_from_verb('undo', false, vim.schedule_wrap(function () vim.cmd 'edit!' end)),
  },
  delete = {
    desc = 'Delete current file',
    complete = true,
    run = cmd_from_verb('delete', true),
  },
  info = {
    desc = 'Show info about current file',
    complete = true,
    run = cmd_from_verb('info', true),
  },
  checkout = {
    desc = 'Checkout file for editing. Deliberately does not work with directories.',
    complete = true,
    run = cmd_from_verb('checkout', false, vim.schedule_wrap(function ()
      vim.cmd 'set noreadonly'
    end))
  },
  checkoutModfiedFiles = {
    desc = 'Checkout all files that 1. are readonly (assumed to be not-checked-out) and 2. have unsaved changes',
    run = function ()
      local bufs = vim.api.nvim_list_bufs()
      local bufs2 = vim.tbl_filter(function (value)
        local isModified = vim.api.nvim_get_option_value('modified', { buf = value })
        local isreadonly = vim.api.nvim_get_option_value('readonly', { buf = value })
        return isModified == true and isreadonly == true
      end, bufs)
      local u = require'tfvc.utils'
      local paths = vim.tbl_map(function (value) return u.get_local_path(nil, value) end, bufs2)
      if #paths > 0 then
        local command = vim.tbl_filter(function (value) return value ~= nil end, paths)
        table.insert(command, 1, 'checkout');
        u.tf_cmd(command, { print_stdout = true }, vim.schedule(function()
          for _, value in ipairs(bufs) do
            vim.api.nvim_set_option_value('readonly', false, { buf = value })
          end
        end))
      end
    end
  },
  showKeybinds = {
    desc = 'Shows default keybinds.... :)',
    run = function () vim.cmd [[:help tfvc-keybinds]] end,
  },
  diff = {
    desc = 'Compare local file to latest server version',
    run = function (opts)
      local args = opts.fargs or {}
      local spec = nil
      if #args > 0 then
        spec = args[1]
      end
      require('tfvc.utils').tf_compare({ versionspec = spec, })
    end
  },
  openWebHistory = {
    desc = 'Open Web History for current File/Directory',
    run = function() require('tfvc.utils').cmd_open_web_history() end,
  },
  status = {
    desc = 'Load Status (Pending Changes) into quickfix list',
    run = function(opts) require('tfvc.status').cmd_status(opts) end,
  },
  loadDiffs = {
    desc = 'Preload Diffs for changed files',
    run = function (opts)
      local force_fresh = opts.bang
      local status = require('tfvc.status')
      status.do_with_pending_changes(force_fresh, vim.schedule_wrap(function(pending_changes)
        local local_paths = vim.tbl_map(function(pending_change)
          return pending_change.Local
        end, pending_changes)

        require('tfvc.utils').preload_versions_for_files(local_paths)
      end))
    end
  },
  clearCache = {
    desc = 'Clear any caches for server file versions and current local changes',
    run = function()
      local c = require('tfvc.utils')
      c.file_versions = {}
      c.pending_changes = nil
    end
  },
  rename = {
    desc = 'Renames/Moves file or directory',
    complete = true,
    run = function()
      local u = require('tfvc.utils')
      local path = u.get_local_path('rename')
      if not path then return end
      local new_path = vim.fn.input {
        prompt = 'Enter new Filename: ',
        default = path,
        cancelreturn = nil,
      }
      if not new_path or new_path == '' then return end
      local cmd = { 'rename', path, new_path }
      u.tf_cmd(cmd, nil, vim.schedule_wrap(function (obj)
        if obj.code == 0 then
          vim.cmd.edit(new_path)
        end
      end))
    end,
  },
  history = {
    desc = 'Shows history of current file in interactive buffer',
    complete = true,
    run = function (args)
      local v = require('tfvc.options')
      local path = get_path_from_cmd_args(args)
      vim.cmd(v.history_open_cmd .. ' tfvc:///history/'.. path)
    end
  }
}

local _, inline_diff = pcall(require, 'unified_diff')
if inline_diff then

  M.commands.inline_diff = {
    desc = 'Experimental: Compare local file to latest server version, (depends on diff executable in PATH)',
    run = function (args)
      local path = get_path_from_cmd_args(args)
      local u = require('tfvc.utils')
      u.tf_get_version_from_versionspec(path, 'T', false, vim.schedule_wrap(function(server_file)
        u.diff_files_inline(server_file, path)
      end))
    end
  }

end

local function path_complete(start)
  if start == '' or start == '.' then
    start = './'
  end

  -- remove escaping any potentially escaped spaces
  -- that we escaped during an earlier path_complete
  -- we won't find any entries with vim.fs.dir with the escaped spaces
  start = start:gsub([[\ ]], ' ')

  --tfvc_comp.start = start
  local paren = start
  local filter = nil
  local iter = nil
  if start:sub(#start) == '/' then
    iter = vim.fs.dir(start)
  else
    paren = vim.fs.dirname(start) .. '/'
    filter = start:gsub(paren, '')
    iter = vim.fs.dir(paren)
  end

  local entries = {}
  for current, type in iter do
    if type == 'file' then
      table.insert(entries, paren .. current)
    end
    if type == 'directory' then
      table.insert(entries, paren .. current .. '/' )
    end
  end

  if filter then
    local prefix = string.lower(paren .. filter)
    entries = vim.tbl_filter(function (path)
      local found = string.lower(path):find(prefix, 1, true)
      return found ~= nil
    end, entries)
  end

  -- we want the path to be parsed as a single argument
  -- and for that vim's commandline needs spaces escaped with back-slash
  entries = vim.tbl_map(function (path)
    return path:gsub(' ', [[\ ]])
  end, entries)

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

local cmd_name = 'TF'
function M.cmd_TF_complete(arg_lead, cmdline, cursor_pos)

  local cmd_keys = vim.tbl_keys(M.commands)
  -- check if we already have a subcommand typed, and do subcommand specific completion
  local subcmd, subcmd_arg_lead = cmdline:match('^' .. cmd_name .. '[!]*%s(%S+)%s(.*)$')
  if subcmd and subcmd_arg_lead and M.commands[subcmd] then
    local subcomplete = M.commands[subcmd].complete
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
    end, cmd_keys)
  end
end

---@param opts vim.api.keyset.create_user_command.command_args
function M.cmd_TF(opts)
  local tfvc = require 'tfvc'
  local fargs = opts.fargs
  local cmd = fargs[1]
  local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}

  local subcommand = tfvc.commands[cmd]
  if subcommand then
    assert(type(subcommand.run) == 'function')
    opts.fargs = args

    local vars = require 'tfvc.options'
    if vars.debug then
      print(vim.inspect(opts))
    end
    subcommand.run(opts)
  else
    vim.notify(cmd_name .. ': Unknown subcommand: ' .. cmd, vim.log.levels.ERROR, { title = 'tfvc.nvim' })
  end
end

--- doesn't initialize this plugin; only sets options
---@param opts tfvc.user_vars
function M.setup(opts)
  local tfvc = vim.g.tfvc or {}
  vim.g.tfvc = vim.tbl_deep_extend('force', tfvc, opts)
end

return M
