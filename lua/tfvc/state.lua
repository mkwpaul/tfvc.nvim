local u = require('tfvc.utils')

---@class tfvcState : tfvc_opts
---@field debug boolean?
---@field pending_changes? table<pendingChange>
---@field file_versions? table<file_version>
 local M = vim.g.tf or {}
 vim.g.tf = M;


---@class tfvc_opts
---@field project_url string should look something like 'https://dev.azure.com/{organization}/{project}/' or 'http://zesrvtfs:8080/tfs/{collection}/{project}'
---@field create_default_mappings boolean
---@field version_control_web_url? string
---@field filter_status_by_cwd? boolean
---@field workfold? workfold the default workfold to use. See $tf vc help workfold 
---@field tf_path? string Full path to the TF executable. If not set, the it will be assumed that the tf executable is in the PATH
---@field tf_leader? string Changes leader for default keymappings. default value: '<leader>t'. Only applies if create_default_mappings is enabled
---@field default_version_spec? version_spec version_spec to use when no version_spec is specified

-- ---@field diff_hide_split? boolean if true, then hide the buffer that is compared against, when using tf diff
-- ---@field diff_open_folds? boolean if true, then don't collapse regions without changes, when using tf diff

---@class subcommand
---@field desc string description
---@field default_mapping? string
---@field run fun(opts: vim.api.keyset.create_user_command.command_args) implementation
---@field complete? any futher completion for subcommand

---@alias version_spec string see :h version_spec

---@class pendingChange
---@field name string
---@field Change string Types of Change. One or more of "Edit, Add, Delete, Encoding" separated by spaces
---@field Local string full local path, normalized via vim.fs.normalize
---@field Relative string local path relative to cwd, normalized via vim.fs.normalize
---@field item string server path
---@field type string Type of Item. "File" or "Directory"

---@class workfold
---@field collection string
---@field serverPath string
---@field localPath string

---@class file_version
---@field version_spec version_spec
---@field local_file string associated local version
---@field server_file string local path to server version

---@class serverFile : file_version
---@field bufType 'serverFile'

---@class localFile
---@field bufType 'localFile'
---@field server_path string
---@field isServerFile? boolean
---@field version_spec? version_spec
---@field pendingChange? pendingChange
---@field file_history? any

---@alias bufInfo serverFile|localFile|nil


M.file_versions = {}

---@param version_spec version_spec
---@param file string
---@return string|nil server_file or null
function M.get_cached_file_version(version_spec, file)
  for _, value in pairs(M.file_versions or {}) do
    if (value.version_spec == version_spec and file == value.local_file) then
      return value.server_file
    end
  end
  return nil
end

function M.tf()
  return M.tf_path or 'tf'
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

---@return workfold?
function M.get_workfold_or_get_cached()

  if M.workfold then
    return M.workfold
  end
  u.tf_cmd({ 'workfold' }, false, function(obj)
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

return M
