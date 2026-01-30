local M = {}

---@type table<file_version>
M.file_versions = {}
---@type table<pending_change>
M.pending_changes = {}
---@type number|nil
M.pending_changes_last_updated = nil
---@type workfold cached from output or user-provided
M.workfold = nil

---@returns a generator that yields lines from a string
---@param str string
local function line_iter(str)
  local lines = vim.split(str, '\n')
  local i = 0
  local iter = {
    current = function() return lines[i] end,
    next = function()
      i = i + 1
      if i <= #lines then
        return lines[i]
      end
      return nil
    end,
  }
  return iter
end

---@param str string
---@return string
local function trim(str)
  if not str then
    return ''
  end
  local rep, _ = string.gsub(str, '^%s*(.-)%s*$', '%1')
  return rep
end

---@param local_path string
function M.get_local_path_relative(local_path)
  local cwd = vim.fs.normalize(vim.fn.getcwd(0))
  if vim.startswith(local_path, cwd) then
    local_path = local_path:sub(#cwd + 1)
  end
  if (local_path:sub(1,1) == '\\') or (local_path:sub(1,1) == '/') then
    local_path = local_path:sub(2)
  end
  return local_path
end

---@param full_path string 
---@return boolean
function M.is_within_workspace(full_path)
  -- paths on windows are case insensitive by default
  -- i think you can optionally make them case sensitive, but lets not worry about that :^)
  -- I also doubt anyone will use this on a linux system where paths are case sensitive
  full_path = vim.fs.normalize(full_path:lower())
  local cwd = vim.fs.normalize(vim.fn.getcwd(0):lower())
  return vim.startswith(full_path, cwd)
end

---@class tf_cmd_opts
---@field print_stdout boolean? should output be printed in messages?
---@field suppress_echo boolean? should command that was ran not be printed?
---@field return_stderr_on_failure boolean? should callback be called despite non-zero exit-code?
---@field debug boolean? print full trace 

--- Executes a command and calls the exit_callback when the command is finished.
---@param command string[] arguments to pass to TF.exe
---@param opts tf_cmd_opts?
---@param callback fun(obj: vim.SystemCompleted)?
function M.tf_cmd(command, opts, callback)

  opts = opts or {}

  local v = require 'tfvc.options'
  table.insert(command, 1, v.executable_path)
  local command_string = table.concat(command, ' ')
  if not opts.suppress_echo then
    print(command_string)
  end

  local _ = vim.system(command, nil, function(obj)
    vim.schedule(function ()
      if obj.code ~= 0 then
        local log = command_string .. '\n' .. 'Code:  ' .. obj.code .. '\n' .. (obj.stderr or '') .. (obj.stdout or '')
        vim.notify(log, vim.log.levels.ERROR)
      end

      if opts.print_stdout and obj.stdout then
        vim.notify(obj.stdout, vim.log.levels.INFO)
      end
    end)

    local o = require('tfvc.options')
    if o.debug then
      local log = 'Job finished: ' .. command_string .. '\n' .. 'Code:  ' .. obj.code .. '\n' .. obj.stderr .. obj.stdout
      vim.schedule(function()
        vim.notify(log, nil, nil)
      end)
    end

    if obj.code ~= 0 and not opts.return_stderr_on_failure then
      return
    end

    -- we only need re-encode output streams
    -- if there's a callback that could possibly make use that output
    if callback then
      local source_enc = v.output_encoding
      if type(source_enc) == 'string' then
        local stdout = nil
        local stderr = nil
        if obj.stdout and obj.stdout ~= '' then
          stdout = vim.iconv(obj.stdout or '', source_enc, 'UTF-8')
        end
        if obj.stderr and obj.stderr ~= '' then
          stderr = vim.iconv(obj.stderr or '', source_enc, 'UTF-8')
        end
        obj = {
          stdout = stdout,
          stderr = stderr,
          code = obj.code,
          signal = obj.signal
        }
      end
      callback(obj)
    end
 end)
end

---@return string filePath uri without the schema prefix and with unescaped URI-escape sequences (%20 = ' ')
function M.file_uri_to_path(uri)
  local path = string.gsub(uri, 'file:///', '')
  path = string.gsub(path, '%%20', ' ')
  return path
end

---@type table<string, fun(buf: number, uri: string):string> dictionary of uri-schemes and functions that resolve a local path for given a buffer and uri with that scheme
M.scheme_mappings = {
  ['file:'] = function(_, uri)
    if uri == 'file://' then
      error('Not a file-buffer', vim.log.levels.ERROR)
    end
    return M.file_uri_to_path(uri)
  end,
  ['tfvc:///files/'] = function (buf, _)
    local p = vim.b[buf].local_path
    assert(type(p) == 'string', [[tfvc:///files buffer must have buffer-varialbe 'local_path' set]])
    return p
  end,
  ['oil:'] = function (buf, _)
    ---@diagnostic disable-next-line: return-type-mismatch
    return require('oil').get_current_dir(buf)
  end,
}

---@param command string? only used for logging when something goes wrong
---@param buf number? vim buffer id, falls back to current buffer if not set
---@return  string?, string? local_path and 'file' or 'directory'
function M.get_local_path(command, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(buf)
  for key, value in pairs(M.scheme_mappings) do
    if vim.startswith(uri, key) then
      return value(buf, uri);
    end
  end
  if command then
    print('Command ' .. command .. 'Invalid for non-file buffers: uri: ' .. uri)
  end
  return nil, nil
end

local function char_to_hex(c) return string.format("%%%02X", string.byte(c)) end

---@param url string?
---@return string?
local function url_encode(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w ])", char_to_hex)
  url = url:gsub(" ", "+")
  return url
end

---@param versionspec versionspec
---@param file string
---@return string|nil server_file or null
local function get_cached_file_version(versionspec, file)
  for _, value in pairs(M.file_versions or {}) do
    if (value.versionspec == versionspec and file == value.local_file) then
      return value.server_file
    end
  end
  return nil
end

---@param path string path to the file to get the version from
---@param versionspec versionspec?
---@param force_fresh boolean? If true, the buffer will be reloaded from the server
---@param callback fun(temp_file_path : string) continuation callback
function M.tf_get_version_from_versionspec(path, versionspec, force_fresh, callback)

  versionspec = versionspec or require('tfvc.options').default_versionspec

  ---@type table<file_version>
  local cache = M.file_versions or {}
  if not force_fresh then
    ---@diagnostic disable-next-line: param-type-mismatch
    local tmp_file = get_cached_file_version(versionspec, path)
    if tmp_file then
      callback(tmp_file)
      return
    end
  end

  local temp = vim.fn.tempname()
  local cmd = { 'vc', 'view', '/version:' .. versionspec, path, '/output:' .. temp }
  M.tf_cmd(cmd, { suppress_echo = true }, vim.schedule_wrap(function(obj)
    if obj.code == 0 then
      if obj.stdout then
        print(obj.stdout)
      end
      ---@type file_version
      local cache_entry = {
        versionspec = versionspec,
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
  end))
end

--[[
$ tf workfold
==============================================================================================
Workspace : localMachine (tfs user)
Collection: [url to server]
 [TfsServerPath]: [MappedLocalPath]
--]]
---@param output string
---@return workfold | nil
local function parse_tf_workfold(output)
  local workfold = {}
  local iter = line_iter(output)
  while iter.next() do
    local line = iter.current()
    if vim.startswith(line, 'Workspace :') then
      workfold.workspace = trim(string.sub(line, 12))
    end
    if vim.startswith(line, 'Collection:') then
      workfold.collection = trim(string.sub(line, 11))
      -- line after collection is " [ServerPath]: [LocalPath]"
      if iter.next() then
        local line_2 = iter.current()
        workfold.serverPath = trim(string.sub(line_2, 1, string.find(line_2, ':') - 1))
        workfold.localPath = trim(string.sub(line_2, string.find(line_2, ':') + 2))
        workfold.localPath = vim.fs.normalize(workfold.localPath)
      end
    end
  end

  if not workfold.serverPath
    or not workfold.localPath
    or not workfold.workspace then
    return nil
  end
  return workfold
end

---@return workfold?
function M.get_workfold_or_get_cached()

  local workfold_from_user = require('tfvc.options').workfold
  if workfold_from_user then return workfold_from_user end
  if M.workfold then return M.workfold end

  M.tf_cmd({ 'workfold' }, nil, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function()
        vim.notify('Failed to get workfold: ' .. vim.inspect(obj), vim.log.levels.ERROR)
      end)
      return
    end

    local workfold = parse_tf_workfold(obj.stdout)
    if not workfold then
      vim.schedule(function()
        vim.notify('Failed to get workfold: ' .. vim.inspect(obj), vim.log.levels.ERROR)
      end)
      return
    end
    M.workfold = workfold
  end)

  return nil
end

---@param path string
---@param relative boolean
---@return string path the mapped path
function M.server_path_to_local_path(path, relative)
  local workfold = M.get_workfold_or_get_cached()
  assert(workfold, 'Workfold must be initialized. Try Again.')
  local localpath, count = path:gsub(workfold.serverPath, workfold.localPath)
  assert(count == 1, 'server_path_to_local_path, gsub of serverroot failed')
  if relative then
    localpath = M.get_local_path_relative(localpath)
  end
  return localpath
end

function M.cmd_open_web_history()
  local v = require 'tfvc.options'
  local workfold = M.get_workfold_or_get_cached()
  assert(workfold, 'Workfold must be initialized. Try Again.')
  assert(v.version_control_web_url, [[User-Option 'version_control_web_url' must be set for command 'open web history']])
  local file = M.get_local_path('open_web_history')
  if not file then
    return
  end

  local serverPath = file:gsub(workfold.localPath, workfold.serverPath)
  local escapedServerPath = url_encode(serverPath) or ''
  escapedServerPath = escapedServerPath:gsub('%%2E', '.')

  local full_url = v.version_control_web_url .. '/?path=' .. escapedServerPath .. '&_a=history'
  if v.debug then
    vim.notify(full_url)
  end
  vim.ui.open(full_url)
end

-- usually called before doing another diff-split
-- so we don't produce more splits than necessary
-- only affects current tab
function M.close_tfvc_diff_wins()
  local cur_win = vim.api.nvim_get_current_win()
  for _, win in pairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf_in_win = vim.api.nvim_win_get_buf(win)
    local is_server = vim.b[buf_in_win].is_server_file

    --vim.api.nvim_get_option_value('diff', { win = win })
    if win ~= cur_win and (is_server or vim.api.nvim_win_get_option(win, 'diff')) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

return M
