local M = {}

---@returns a generator that yields lines from a string
---@param str string
function M.line_iter(str)
  local lines = vim.split(str, '\n')
  local i = 0
  local iter = {
    current = function()
      return lines[i]
    end,
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
function M.trim(str)
  if not str then
    return ''
  end
  return string.gsub(str, '^%s*(.-)%s*$', '%1')
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

--- Executes a command and calls the exit_callback when the command is finished.
-- ---@param exit_callback nil | fun(obj: vim.SystemCompleted)
-- ---@param space_separated string[]
-- ---@param print_stdout boolean
-- ---@deprecated use tf_cmd2 instead
-- function M.tf_cmd(space_separated, print_stdout, exit_callback)
--   local opts = { print_stdout = print_stdout }
--   M.tf_cmd2(space_separated, opts, exit_callback)
-- end

---@class tf_cmd_opts
---@field print_stdout boolean? should output be printed in messages?
---@field suppress_echo boolean? should command that was ran not be printed?
---@field return_stderr_on_failure boolean? should callback be called despite non-zero exit-code?
---@field debug boolean? print full trace 

---@param command string[] arguments to pass to TF.exe
---@param opts tf_cmd_opts?
---@param callback fun(obj: vim.SystemCompleted)?
function M.tf_cmd2(command, opts, callback)

  opts = opts or {}

  local s = require('tfvc.state')
  table.insert(command, 1, s.tf())
  local command_string = table.concat(command, ' ')
  if not opts.suppress_echo then
    print('cmd:' .. command_string)
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

    local state = require('tfvc.state')
    if state.debug then
      local log = 'Job finished: ' .. command_string .. '\n' .. 'Code:  ' .. obj.code .. '\n' .. obj.stderr .. obj.stdout
      vim.schedule(function()
        vim.notify(log, nil, nil)
      end)
    end

    if obj.code ~= 0 and not opts.return_stderr_on_failure then
      return
    end

    if callback then
      if type(vim.g.tf_output_encoding) == 'string' then
        local stdout = nil
        local stderr = nil
        if obj.stdout and obj.stdout ~= '' then
          stdout = vim.iconv(obj.stdout or '', vim.g.tf_output_encoding, 'UTF-8')
        end
        if obj.stderr and obj.stderr ~= '' then
          stderr = vim.iconv(obj.stderr or '', vim.g.tf_output_encoding, 'UTF-8')
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
local schemeMappers = {
  ['file:'] = function(buf, uri)
    return M.file_uri_to_path(uri)
  end,
  ['oil:'] = function (buf, uri)
    ---@diagnostic disable-next-line: return-type-mismatch
    return require('oil').get_current_dir(buf)
  end
}

function M.get_current_file(command, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(buf)
  for key, value in pairs(schemeMappers) do
    if vim.startswith(uri, key) then
      return value(buf, uri);
    end
  end
  print('Command ' .. command .. 'Invalid for non-file buffers: uri:' .. uri)
  return nil
end

local function char_to_hex(c)
  return string.format("%%%02X", string.byte(c))
end

local function hex_to_char(x)
  return string.char(tonumber(x, 16))
end

---@param url string?
---@return string?
function M.url_encode(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w ])", char_to_hex)
  url = url:gsub(" ", "+")
  return url
end

---@param url string?
---@return string?
function M.url_decode(url)
  if url == nil then
    return
  end
  url = url:gsub("+", " ")
  url = url:gsub("%%(%x%x)", hex_to_char)
  return url
end


---@param path string path to the file to get the version from
---@param versionspec version_spec 
---@param force_fresh boolean? If true, the buffer will be reloaded from the server
---@param callback fun(temp_file_path : string) continuation callback
function M.tf_get_version_from_versionspec(path, versionspec, force_fresh, callback)
  local s = require 'tfvc.state'
  versionspec = versionspec or s.default_version_spec

  ---@type table<file_version>
  local cache = s.file_versions or {}
  if not force_fresh then
    local tmp_file = s.get_cached_file_version(versionspec, path)
    if tmp_file then
      callback(tmp_file)
      return
    end
  end

  local temp = vim.fn.tempname()
  local cmd = { 'vc', 'view', '/version:' .. versionspec, path, '/output:' .. temp }
  M.tf_cmd2(cmd, nil, vim.schedule_wrap(function(obj)
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
  end))
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

  local spec = vim.fn.input { prompt = prompt, default = '', cancelreturn = 'T' }
  return spec
end

return M
