local u = require('tfvc.utils')

---@class pendingChange
---@field name string
---@field Change string Types of Change. One or more of "Edit, Add, Delete, Encoding" separated by spaces
---@field Local string local path, normalized via vim.fs.normalize
---@field Relative string local path relative to cwd, normalized via vim.fs.normalize
---@field item string server path
---@field type string Type of Item. "File" or "Directory"

---@class workfold
---@field collection string
---@field serverPath string
---@field localPath string

---@class file_version
---@field version_spec string version_spec
---@field local_file string associated local version
---@field server_file string local path to server version

---@class tfvcState
---@field debug boolean
---@field pending_changes table<pendingChange> | nil
---@field pending_changes_last_updated number | nil
---@field file_versions table<file_version>
---@class tfvcState
local M = {
  debug = false,
  default_status_filter = 'All',
  file_versions = {},
}

---@param version_spec string
---@param file string
---@return string | nil server_file or null
function M.get_cached_file_version(version_spec, file)
  for _, value in pairs(M.file_versions) do
    if (value.version_spec == version_spec and file == value.local_file) then
      return value.server_file
    end
  end
  return nil
end

function M.tf()
  return vim.g.tf_path or 'tf'
end

function M.print()
  vim.schedule(function()
    vim.notify (vim.inspect(M))
  end)
end

--[[
// tf workfold output
$ tf workfold
==============================================================================================
Workspace : localMachine (tfs user)
Collection: [url to server]
 [TfsServerPath]: [MappedLocalPath]
--]]
---@return workfold | nil
local function parse_tf_workfold(output)
  local workfold = {}
  local iter = u.line_iter(output)

  while (iter.next()) do
    local line = iter.current()
    if (vim.startswith(line, 'Workspace :')) then
      workfold.workspace = u.trim(string.sub(line, 12))
    end
    if (vim.startswith(line, 'Collection:')) then
      workfold.collection = u.trim(string.sub(line, 11))
      -- line after collection is " [ServerPath]: [LocalPath]"
      if (iter.next()) then
        local line_2 = iter.current()
        workfold.serverPath = u.trim(string.sub(line_2, 1, string.find(line_2, ':') - 1))
        workfold.localPath = u.trim(string.sub(line_2, string.find(line_2, ':') + 2))
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

function M.get_workfold_or_get_cached()
  if vim.g.workfold then
    return vim.g.workfold
  end
  u.tf_cmd({ 'workfold' }, function(obj)
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

    vim.g.workfold = workfold
  end)
end

return M
