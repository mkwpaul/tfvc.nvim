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
---@param exit_callback nil | fun(obj: vim.SystemCompleted)
---@param space_separated string[]
---@param print_stdout boolean
function M.tf_cmd(space_separated, print_stdout, exit_callback)

  local s = require('tfvc.state')
  table.insert(space_separated, 1, s.tf())
  local command_string = table.concat(space_separated, ' ')
  print('cmd:' .. command_string)

  local _ = vim.system(space_separated, nil, function(obj)
    vim.schedule(function ()
      if obj.code ~= 0 then
        local log = command_string .. '\n' .. 'Code:  ' .. obj.code .. '\n' .. obj.stderr .. obj.stdout
        vim.notify(log, vim.log.levels.ERROR)
      end

      if print_stdout and obj.stdout then
        vim.notify(obj.stdout, vim.log.levels.INFO)
      end
    end)

    if obj.code ~= 0 then
      return
    end

    local state = require('tfvc.state')
    if state.debug then
      local log = 'Job finished: ' .. command_string .. '\n' .. 'Code:  ' .. obj.code .. '\n' .. obj.stderr .. obj.stdout
      vim.schedule(function()
        vim.notify(log, nil, nil)
      end)
    end
    if exit_callback then
      exit_callback(obj)
    end
 end)
end

---@return string filePath uri without the schema prefix and with unescaped URI-escape sequences (%20 = ' ')
function M.file_uri_to_path(uri)
  local path = string.gsub(uri, 'file:///', '')
  path = string.gsub(path, '%%20', ' ')
  return path
end

function M.get_current_file(command, bufId)
  bufId = bufId or vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(bufId)
  if not vim.startswith(uri, 'file:///') then
    print('Command ' .. command .. 'Invalid for non-file buffers: uri:' .. uri)
    return nil
  end

  local path = M.file_uri_to_path(uri)
  return path
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

return M
