local M = {}
local u = require('tfvc.utils')
local s = require('tfvc.state')

M.state = s

vim.g.default_versionspec = "T"

function M.cmd_tf_checkout()
  local path = u.get_current_file('tf_checkout')
  if not path then
    return
  end
  local cmd =  {  'vc', 'checkout', path, }
  u.tf_cmd(cmd, function(obj)
    if obj.code == 0 then
      vim.schedule(function() vim.cmd 'set noreadonly' end)
    end
  end)
end

---@param opts table|nil
---@param path string|nil
-- Undoes any pending changes to the current file
function M.cmd_tf_undo(opts, path)
  if not opts then
    opts = {}
  end
  path = path or u.get_current_file('tf_undo')
  if not path then
    return
  end
  u.tf_cmd { 'vc' ,'undo', path }
end

function M.cmd_tf_add()
  local path = u.get_current_file('tf_add')
  if not path then
    return
  end
  u.tf_cmd { 'vc' ,'add', path }
end

---@alias version_spec string see :h version_spec
---
---@param versionspec version_spec? Which Versionspec to use. See :h tfvc.version_spec
---@param buf_id number? Which Buffer to use.
---@param force_fresh boolean? If true, the buffer will be reloaded from the server
function M.tf_compare(versionspec, buf_id, force_fresh)

  local path = u.get_current_file('tf_compare', buf_id)
  if not path then
    return
  end
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  versionspec = versionspec or vim.g.default_versionspec

  M.tf_get_version_from_versionspec(path, versionspec, force_fresh, function(temp)
    -- we need to disable buf mode for other buffers
    -- otherwise we end up diffing with all those files too
    --
    -- TODO:
    -- bufdo navigates us to the last buffer, so we need to navigate back to the buffer we had
    -- do this without bufdo so we don't totally screw up the jump list and manually navigate back
    vim.cmd('bufdo diffoff!')
    vim.api.nvim_set_current_buf(buf_id)
    vim.cmd.diffsplit(temp)
  end)
end

---@param path string path to the file to get the version from
---@param versionspec string 
---@param force_fresh boolean? If true, the buffer will be reloaded from the server
---@param callback fun(temp_file_path : string) continuation callback
function M.tf_get_version_from_versionspec(path, versionspec, force_fresh, callback)
  versionspec = versionspec or vim.g.default_versionspec

  ---@type table<file_version>
  local cache = s.file_versions
  if not force_fresh then
    local tmp_file = s.get_cached_file_version(versionspec, path)
    if tmp_file then
      callback(tmp_file)
      return
    end
  end

  local temp = vim.fn.tempname()
  local cmd = { 'vc', 'view', '/version:' .. versionspec, path, '/output:' .. temp }
  u.tf_cmd(cmd, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        if obj.stdout then
          print(obj.stdout)
        end
        ---@type file_version
        local cache_entry = {
          version_spec = versionspec,
          local_file = path,
          server_file = temp
        }

        -- remove existing cache entry if any
        for i, value in ipairs(cache) do
          if value.local_file == cache_entry.local_file then
            table.remove(cache, i)
            break
          end
        end
        table.insert(cache, cache_entry)
        callback(temp)
      end
    end)
  end)

end

---@param files string[] list of file paths
---@param version_spec version_spec
function M.preload_versions_for_files(files, version_spec, force_fresh)

  -- either get existing bufferId for create a new buffer for all files
  vim.print(vim.inspect(files))

  for _, file in pairs(files) do
    M.tf_get_version_from_versionspec(file, version_spec, force_fresh, function(temp)
      if s.debug then
        print("Preloaded Version " .. version_spec ..  "  for " .. file .. ": " .. temp)
      end
    end)
  end
end


function M.preload_pending_changes(force_fresh)
  local status = require('tfvc.status')
  local version_spec = M.get_versionspec_from_user()
  status.do_with_pending_changes(force_fresh, function(pending_changes)
    vim.schedule(function()
      local local_paths = vim.tbl_map(function(pending_change) return pending_change.Local end, pending_changes)
      M.preload_versions_for_files(local_paths, version_spec)
    end)
  end)
end

---@param opts cmd_call_args
local function cmd_tf_diff(opts)
  opts = opts or {}
  local args = opts.fargs or {}
  local spec = vim.g.default_versionspec or "T"
  if #args > 0 then
    spec = args[1]
  end
  local fresh = opts.bang
  M.tf_compare(spec, nil, fresh)
end

function M.get_versionspec_from_user()
  local prompt =
[[Versionspec:
    Date/Time         D"any .NET Framework-supported format"
                      or any of the date formats of the local machine
    Changeset number  Cnnnnnn
    Label             Llabelname
    Latest version    T
    Workspace         Wworkspacename;workspaceowner

VersionSpec > ]]

  local spec = vim.fn.input { prompt = prompt, default = "", cancelreturn = vim.g.default_versionspec }
  return spec
end

function M.cmd_tf_preload_status()
  local status = require('tfvc.status')
  status.get_pending_changes_async(function()
    vim.schedule(function()
      vim.print('TFS: Pending Changes loaded: (' .. #s.pending_changes or 'nil' .. ') Changes')
    end)
  end)
end

M.commands = {
  ['TFAdd'] = { run = M.cmd_tf_add, desc = 'TFS: Add current File to Source Control', default_mapping = 'a' },
  ['TFUndo'] = { run = M.cmd_tf_undo, desc = 'TFS: Undo Pending Changes', default_mapping = 'u' },
  ['TFCheckout'] = { run = M.cmd_tf_checkout, desc = "TFS: Checkout file", default_mapping = 'c' },
  ['TFDiff'] = { run = cmd_tf_diff, desc = 'TFS: Compare local file to Server Version', default_mapping = 'l', nargs = '?', bang = true },
  ['TFHistory'] = { run = function() require('tfvc.history').cmd_open_web_history() end, desc = 'TFS: Open Web History for current File/Directory', default_mapping = 'w' },
  ['TFStatus'] = { run = function(opts) require('tfvc.status').cmd_show_telescope_finder(opts) end, desc = 'TFS: Status', nargs = '*', bang = true },
  ['TFLoadDiffs'] = { desc = 'TFS: Preload Diffs for changed files', default_mapping = 'pd',
    run = function(opts)
      opts = opts or {}
      M.preload_pending_changes(opts.bang or false)
    end},
  ['TFLoadStatus'] = { run = M.cmd_tf_preload_status, desc = 'TFS: Load Pending Changes', default_mapping = 'ps' },
}

M.keymaps = {
  { default_mapping = 'ss', desc = 'TFS: Status', run = '<cmd>TFStatus cached in_cwd<CR>' },
  { default_mapping = 'sf', desc = 'TFS: Status', run = '<cmd>TFStatus fresh in_cwd<CR>' },
  { default_mapping = 'd', desc = 'TFS: Diff with specific Version', run = function()
    M.tf_compare(M.get_versionspec_from_user())
  end},
}

---@param leader string 
function M.init_default_mappings(leader)
  for _, mapping in pairs(M.commands) do
    if mapping.default_mapping then
      local motion = leader .. mapping.default_mapping
      vim.keymap.set('n', motion, mapping.run, { desc = mapping.desc })
    end
  end
  for _, mapping in pairs(M.keymaps) do
      local motion = leader .. mapping.default_mapping
      vim.keymap.set('n', motion, mapping.run, { desc = mapping.desc })
  end
end

---@class tfvc_opts
---@field create_default_mappings boolean
---@field version_control_web_url string | nil
---@field workfold workfold | nil
---@field tf_path string | nil Full path to the TF executable. If not set, the it will be assumed that the tf executable is in the PATH
---@field tf_leader string | nil Changes leader for default keymappings. default value: '<leader>t'. Only applies if create_default_mappings is enabled

---@class cmd_call_args
---@field name string Command name
---@field args string The args passed to the command, if any <args>
---@field fargs table The args split by unescaped whitespace (when more than one argument is allowed), if any <f-args>
---@field nargs string Number of arguments `:command-nargs`
---@field bang boolean "true" if the command was executed with a ! modifier <bang>
---@field line1 number The starting line of the command range <line1>
---@field line2 number The final line of the command range <line2>
---@field range number The number of items in the command range: 0, 1, or 2 <range>
---@field count number Any count supplied <count>
---@field reg string The optional register, if specified <reg>
---@field mods string Command modifiers, if any <mods>
---@field smods table Command modifiers in a structured format.

---@type tfvc_opts
M.default_opts = {
  create_default_mappings = false,
  version_control_web_url = nil,
  workfold = nil,
  tf_path = nil,
  tf_leader = '<leader>t',
}

---@param opts tfvc_opts | nil
function M.setup(opts)
  opts = vim.tbl_deep_extend('keep', opts, M.default_opts)

  for cmd, mapping in pairs(M.commands) do
    local cmd_opts = { desc = mapping.desc }
    if mapping.nargs then
      cmd_opts.nargs = mapping.nargs
    end
    if mapping.bang then
      cmd_opts.bang = mapping.bang
    end
    vim.api.nvim_create_user_command(cmd, mapping.run, cmd_opts)
  end
  opts = opts or {}
  if opts.create_default_mappings then
      M.init_default_mappings(opts.tf_leader)
  end
  if opts.version_control_web_url then
      vim.g.version_control_web_url = opts.version_control_web_url
  end
  if opts.workfold then
      vim.g.tfvc_workfold = opts.workfold
  end
  if opts.tf_path then
      vim.g.tf_path = opts.tf_path
  end
end

return M
