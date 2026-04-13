--- proxy obj for user-options access,
--- don't use this to set options
---@type tfvc.user_vars
---@diagnostic disable-next-line: missing-fields 
local M = {}

M.option_definitions = {
  debug = { fallback = false, },
  diff_no_split = { fallback = false,  },
  diff_open_folds = { fallback = false, },
  filter_status_by_cwd = { fallback = true, },
  blocking = { fallback = false },
  default_versionspec = { fallback = 'T', },
  executable_path = { fallback = 'TF', },
  history_entry_limit = { fallback = 300, },
  history_open_cmd = { fallback = 'e', },
  diff_open_cmd = { fallback = 'above split', },
  output_encoding = { fallback = 'UTF-8', },
  version_control_web_url = { fallback = nil, type = 'string' },
  workfolds = { fallback = {}, type = 'table' },
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

function M.get_option(key)
  local var = assert(M.option_definitions[key], key .. ' is invalid key for user-vers')

  local opt_type = type(var.fallback) or var.type
  if opt_type == "nil" then
    opt_type = assert(var.type)
  end

  -- direct global tfvc_[key] have precedence over
  -- values on the vim.g.tfvc object
  -- so that stuff can be more easily overwritten with :let g:tfvc_
  local value = nil
  value = vim.g['tfvc_'..key]

  local function assert_type(v)
    local valtype = type(v)
    if valtype ~= opt_type then
      error(string.format('Option "%s" expects value of type "%s" but provided value was of type "%s"', key, opt_type, valtype))
    end
    return v
  end

  if value ~= nil then
    return assert_type(value), true
  end

  local tfObj = vim.g.tfvc
  if tfObj then
    value = tfObj[key]
    if value ~= nil then
      return assert_type(value), true
    end
  end

  assert(var.fallback ~= nil, 'Tried to access option "'..key..'" but no value was provided and option has no fallback')
  return var.fallback, false
end

setmetatable(M, {
  __index = function (_, k)
    local val = M.get_option(k)
    return val
  end
})

return M
