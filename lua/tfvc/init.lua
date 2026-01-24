local M = {}

---@param opts { diff_no_split:boolean?, diff_open_folds:boolean?, versionspec:string? }?
function M.tf_compare(opts)
  opts = opts or {}
  local u = require 'tfvc.utils'
  local path = u.get_local_path('tf_compare', 0)
  if not path then
    return
  end

  local versionspec = opts.versionspec or require('tfvc.options').default_versionspec
  u.close_tfvc_diff_wins()
  vim.cmd(':diffo!')
  vim.cmd.diffsplit('tfvc:///files/'..versionspec..'/'..path)

  local o = require 'tfvc.options'
  if opts.diff_no_split == nil then opts.diff_no_split = o.diff_no_split  end
  if opts.diff_open_folds == nil then opts.diff_open_folds = o.diff_open_folds end
  if opts.diff_no_split then vim.cmd ':norm q' end
  if opts.diff_open_folds then vim.cmd ':norm zr' end
end

function M.toggle_diff()
  local was_diff =  vim.api.nvim_win_get_option(0, 'diff')
  if vim.b[0].is_server_file then
    local v = require('tfvc.options')
    if vim.b[0].versionspec == v.default_versionspec then
      vim.api.nvim_win_close(0, true)
      return
    end
  end
  if was_diff then
    require('tfvc.utils').close_tfvc_diff_wins()
    vim.cmd(':diffo!')
  else
    M.tf_compare()
  end
end

---@param files string[] list of file paths
---@param versionspec versionspec?
function M.preload_versions_for_files(files, versionspec, force_fresh)
  local u = require 'tfvc.utils'
  for _, file in pairs(files) do
    u.tf_get_version_from_versionspec(file, versionspec, force_fresh, function () end)
  end
end

local function cmd_from_verb(verb, pass_path, print_stdout, callback)
  ---@param opts vim.api.keyset.create_user_command.command_args
  return function(opts)
    local args = {}
    local path = nil
    local u = require('tfvc.utils')
    if pass_path then
      path = #opts.fargs > 0 and opts.fargs[1] or u.get_local_path(verb)
      args = { 'vc' , verb, path }
    else
      args = { 'vc', verb }
    end
    u.tf_cmd(args, { print_stdout = print_stdout } , callback)
  end
end

---@class subcommand
---@field desc string
---@field run fun(opts: vim.api.keyset.create_user_command.command_args)

---@type table<string,subcommand>
M.commands = {
  add = {
    desc = 'Add current file to version sontrol',
    run = cmd_from_verb('add', true, false)
  },
  undo = {
    desc = 'Undo changes in current file',
    run = cmd_from_verb('undo', true, false, vim.schedule_wrap(function () vim.cmd 'edit!' end)),
  },
  delete = {
    desc = 'Delete current file',
    run = cmd_from_verb('delete', true, true)
  },
  info = {
    desc = 'Show info about current file',
    run = cmd_from_verb('info', true, true)
  },
  checkout = {
    desc = 'Checkout file for editing',
    run = cmd_from_verb('checkout', true, false, function ()
      vim.schedule(function() vim.cmd 'set noreadonly' end)
    end)
  },
  diff = {
    desc = 'Compare local file to latest server version',
    run = function (opts)
      local args = opts.fargs or {}
      local spec = nil
      if #args > 0 then
        spec = args[1]
      end
      M.tf_compare({ versionspec = spec, })
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

        M.preload_versions_for_files(local_paths)
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
    complete = 'file',
    run = function (opts)
      local u = require('tfvc.utils')
      local path = #opts.fargs > 0 and opts.fargs[1] or u.get_local_path('rename')
      if not path then return end
      local new_path = vim.fn.input({
        prompt = 'Enter new Filename: ',
        default = path,
        cancelreturn = nil,
      })
      if not new_path or new_path == '' then return end
      local cmd = { 'rename', path, new_path}
      u.tf_cmd(cmd, nil, vim.schedule_wrap(function (obj)
        if obj.code == 0 then
          vim.cmd.edit(new_path)
        end
      end))
    end,
  },
  history = {
    desc = 'Shows history of current file in interactive buffer',
    complete = 'file',
    run = function (opts)
      local u = require('tfvc.utils')
      local v = require('tfvc.options')
      local path = #opts.fargs > 0 and opts.fargs[1] or u.get_local_path('history') or '.'
      local opening_cmd = v.history_open_cmd
      vim.cmd (opening_cmd .. ' tfvc:///history/'.. path)
    end
  }
}

--- doesn't initialize this plugin sets options
---@param opts tfvc_user_vars
function M.setup(opts)
  local tf = vim.g.tf or {}
  vim.g.tf = vim.tbl_deep_extend('force', tf, opts)
end

return M
