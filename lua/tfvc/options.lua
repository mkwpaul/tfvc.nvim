---@class tfvc_user_vars class defining all recognized variables that control behavior of this plugin
---@field debug boolean? verbose output for debugging
---@field default_versionspec versionspec? versionspec to use with commands when no version_spec is specified, defaults to 'T' which indicates to use the latest version
---@field diff_no_split? boolean if true, then hide the buffer that is compared against, when using tf diff
---@field diff_open_folds? boolean if true, then don't collapse regions without changes, when using tf diff
---@field filter_status_by_cwd boolean? When using tf status, only show changed files under the current working directory
---@field executable_path string? Full path to the TF executable. If not set, the it will be assumed that the tf executable is in the PATH
---@field history_entry_limit number? number of entries to load in history buffers
---@field history_open_cmd? string command to use when navigating to tfvc:/// paths via commands, should be one of 'edit', 'split', 'vsplit', 'above split', 'top' etc. see :h window
---@field output_encoding string? if specified, use iconv to convert output from tf.exe from the specified encoding to utf-8, value is passed as-is to iconv, so it should be an encoding
---@field version_control_web_url string this should look something like 'http://{host}/tfs/{collection}/{project}/_versionControl'
---@field workfold? workfold the default workfold to use. See $tf vc help workfold 
---@field diff_open_cmd? string command to use when opening diff views from history or changeset buffers, should be one of 'edit', 'split', 'vsplit', 'above split', 'top' etc. see :h window

local variables = {
  debug = { fallback = false, },
  default_versionspec = { fallback = 'T', },
  diff_no_split = { fallback = false, },
  diff_open_folds = { fallback = false, },
  executable_path = { fallback = 'TF', },
  filter_status_by_cwd = { fallback = true, },
  history_entry_limit = { fallback = 300, },
  history_open_cmd = { fallback = 'e', },
  output_encoding = { fallback = nil, },
  version_control_web_url = { fallback = nil, },
  workfold = { fallback = nil, },
  diff_open_cmd = { fallback = 'above split', },
}

--[[
This proxy-object provides unified access to user-variables controlling the
behavior of this plugin. Instead of accessing various variables on vim.g all
over the code, or fields on a vim.g.tfvc object, or retrieving options from some
other lua table filled via some setup() call or other API,...insetad of that,
we just always use this proxy-object. That way, the way the user specified the
variable is decoupled from how we access it.

It additionally lets us support, mix and even layer all different ways options
could be specified.

it also lets us nicely prevent typo errors in our code, since we can check
the key against the table of known variables when indexing.

...AND it eliminates having to deal with fallbacks and checks everywhere!
We can define fallback values in a centralized place once... (here)
and callsites don't have to know about fallbacks and can just assume that 
they have a valid value when they access the variable, provided that variable has a fallback.

Current precedence (from highest to lowest) is:
1. Individual field on vim.g prefixed with 'tfvc_'
   Highest so it's easier to set variables interactively
   by executing ':let g:tfvc_default_versionspec = .....' for example
2. field on vim.g.tf table (like vim.g.tfvc.default_versionspec = 'T')
2. values passed to setup()

Note that the table passed to require('tfvc').setup is just merged into vim.g.tfvc
so precedence depends on what value was set last.
]]

--- proxy obj for user-options access,
--- don't use this to set options
---@type tfvc_user_vars
---@diagnostic disable-next-line: missing-fields 
local M = {}

setmetatable(M, {
  __index = function (_, k)
    local var = variables[k]
    assert(var, vim.inspect(k) .. " is invalid key for user-vers")

    -- direct global tfvc_[key] have precedence over
    -- values on the vim.g.tfvc object
    -- so that stuff can be more easily overwritten with :let g:tfvc_
    local value = nil
    value = vim.g['tfvc_'..k]

    if value ~= nil then
      return value
    end

    local tfObj = vim.g.tfvc
    if tfObj then
      value = tfObj[k]
      if value ~= nil then
        return value
      end
    end

    return var.fallback
  end
})

return M

---@alias versionspec string see :h versionspec

---@class pending_change
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
---@field versionspec versionspec
---@field local_file string associated local version
---@field server_file string local path to server version

---@class serverFile : file_version
---@field bufType 'serverFile'

---@class localFile
---@field bufType 'localFile'
---@field server_path string
---@field isServerFile? boolean
---@field versionspec? versionspec
---@field pendingChange? pending_change
---@field file_history? any

---@alias bufInfo serverFile|localFile|nil
