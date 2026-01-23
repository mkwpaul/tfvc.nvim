
---@class tfvcState caches this plugin uses to avoid quering the same data twice
---@field pending_changes? table<pendingChange>
---@field pending_changes_last_updated number|nil
---@field file_versions? table<file_version>
---@field workfold workfold cached from output or user-provided
---@field user_vars tfvc_user_vars proxy obj for user-options access
 local M = {}

---@class tfvc_user_vars class defining all recognized variables that control behavior of this plugin
---@field debug boolean?
---@field default_versionspec version_spec? version_spec to use when no version_spec is specified
---@field diff_no_split boolean?
---@field diff_open_folds boolean?
---@field executable_path string? Full path to the TF executable. If not set, the it will be assumed that the tf executable is in the PATH
---@field filter_status_by_cwd boolean?
---@field history_entry_limit number?
---@field history_open_cmd? string
---@field output_encoding string?
---@field project_url string should look something like 'https://dev.azure.com/{organization}/{project}/' or 'http://zesrvtfs:8080/tfs/{collection}/{project}'
---@field version_control_web_url string
---@field workfold? workfold the default workfold to use. See $tf vc help workfold 

local user_vars_defs = {
  debug = {
    fallback = false,
    desc = 'verbose output',
  },
  default_versionspec = {
    fallback = 'T',
    desc = 'version_spec version_spec to use when no version_spec is specified',
  },
  diff_no_split = {
    fallback = false,
    desc = "when diff'ing a file, should the diff be inlined?",
  },
  diff_open_folds = {
    fallback = false,
    desc = "when diff'ing a file, should the regions created by vim's diff mode be expanded?",
  },
  executable_path = {
    fallback = 'TF',
    desc = 'Full path to the TF executable. If not set, the it will be assumed that the tf executable is in the PATH',
  },
  filter_status_by_cwd = {
    fallback = true,
    desc = '',
  },
  history_entry_limit = {
    fallback = 300,
    desc = 'how much history entries to display when loading a history buffer'
  },
  history_open_cmd = {
    fallback = 'e',
    desc = 'command to use when navigating to tfvc:/// paths via commands, should be one of edit, split, vsplit etc. ',
  },
  output_encoding = {
    fallback = nil,
    desc = 'if specified, use iconv to convert output from tf.exe from the specified encoding to utf-8, value is passed as-is to iconv, so it should be an encoding',
  },
  project_url = {
    fallback = nil,
    desc = "should look something like 'https://dev.azure.com/{organization}/{project}/' or 'http://zesrvtfs:8080/tfs/{collection}/{project}"
  },
  version_control_web_url = {
    fallback = nil,
    desc = "TODO"
  },
  workfold = {
    fallback = nil,
  },
}

local optsProxy = {}
setmetatable(optsProxy, {
  __index = function (t, k)
    local var = user_vars_defs[k]

    if not var then
      error('invalid key into tf-options' .. vim.inspect(k), vim.log.levels.ERROR)
      return nil
    end

    -- direct global tf_[key] have precedence over
    -- values on the vim.g.tf object
    -- so that stuff can be more easily overwritten
    -- using :let g:tf_[key] = value
    local value = nil
    value = vim.g['tf_'..k]

    if value ~= nil then
      --print('retrieved ' .. k .. ' from vim.g.tf_' .. k .. '. Value was ' .. value)
      return value
    end

    local tfObj = vim.g.tf
    if tfObj then
      value = tfObj[k]
      if value ~= nil then
        -- print('retrieved ' .. k .. ' from vim.g.tf.' .. k .. '. Value was ' .. value)
        return value
      end
    end

    return var.fallback
  end
})


M.user_vars = optsProxy

-- ---@field diff_hide_split? boolean if true, then hide the buffer that is compared against, when using tf diff
-- ---@field diff_open_folds? boolean if true, then don't collapse regions without changes, when using tf diff

---@class subcommand
---@field desc string description
---@field default_mapping? string
---@field run fun(opts: vim.api.keyset.create_user_command.command_args) implementation
---@field complete? any futher completion for subcommand
-- ---@field plug_mapping? string

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
  local u = require('tfvc.utils')
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
  if M.user_vars.workfold then
    return M.user_vars.workfold
  end

  local u = require('tfvc.utils')
  u.tf_cmd({ 'workfold' }, nil, function(obj)
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
