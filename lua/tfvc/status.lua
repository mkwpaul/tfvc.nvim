local u = require('tfvc.utils')
local xmlparser = require('tfvc.xmlparser')
local s = vim.g.tf

local M = {}

---@class xmlPendingChange
---@field chg string Types of Change One or more of "Edit, Add, Delete, Encoding" separated by spaces
---@field chgEx string
---@field ct string
---@field date string
---@field enc string
---@field hash string
---@field item string
---@field itemid string
---@field len string
---@field local string
---@field pcid string
---@field psn string
---@field pso string
---@field psod string
---@field type string
---@field uhash string
---@field ver string

---@param node xmlNode
---@param changes table<pendingChange>
local function iter_xml(node, changes)
  if node.tag == 'PendingChange' then
    ---@type xmlPendingChange
    local props = node.attrs
    local pendingChange = {
      Change = props.chg,
      Local = vim.fs.normalize(props["local"]),
      item = props.item,
      type = props["type"],
      name = vim.fs.basename(props["local"])
    }
    table.insert(changes, pendingChange)
  end

  if node.children ~= nil then
    for _, v in pairs(node.children) do
      iter_xml(v, changes)
    end
  end
end

---@param status_xml string 
---@return table<pendingChange>
local function parse_status_xml(status_xml)
  local doc = xmlparser.parse(status_xml, false)
  local changes = {}
  iter_xml(doc, changes)
  return changes
end

---@param callback function (table<pendingChange>)
function M.get_pending_changes_async(callback)
  u.tf_cmd ({ 'status', '/format:xml' }, false, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function()
        vim.notify('Failed to get pending changes: ' .. vim.inspect(obj), vim.log.levels.ERROR)
      end)
      return
    end
    local changes = parse_status_xml(obj.stdout)
    s.pending_changes = changes
    s.pending_changes_last_updated = os.time()
    callback(changes)
  end)
end

---@param force_fresh boolean 
---@param callback fun(table<pendingChange>)
function M.do_with_pending_changes(force_fresh, callback)
  local pending_changes = s.pending_changes
  if pending_changes == nil or force_fresh then
    M.get_pending_changes_async(callback)
  else
    callback(pending_changes)
  end
end

function M.change_type_to_icons(change)
  local words = vim.split(change, ' ', { plain=true, trimempty=true})
  local result = {}
  for _, value in pairs(words) do
    if value == 'Add' then table.insert(result, '+') end
    if value == 'Edit' then table.insert(result, '✎') end
    if value == 'Delete' then table.insert(result, '🗑') end
    if value == 'Encoding' then table.insert(result, '🗎') end
    if value == 'Rollback' then table.insert(result, '←') end
  end
  return table.concat(result, ' ')
end

---@class pending_chagnes_opts
---@field fresh boolean 
---@field in_cwd boolean 

function M.load_pending_changes_into_qf(fresh, in_cwd)
  M.do_with_pending_changes(fresh, function (pending_changes)
    vim.schedule(function()
      if in_cwd then
        pending_changes = vim.tbl_filter(function(change)
          return u.is_within_workspace(change.Local)
        end,
        pending_changes)
      end
      local qf_entries = vim.tbl_map(function (change)
        return {
          filename = change.Local,
          valid = true,
          text = M.change_type_to_icons(change.Change) .. ' ' .. change.Change
        }
      end, pending_changes)

      vim.fn.setqflist(qf_entries)
      vim.cmd.copen()
    end)
  end)
end

---@param opts vim.api.keyset.create_user_command.command_args
function M.parse_cmd_args(opts)
  local args = opts.fargs or {}

  local in_cwd = s.filter_status_by_cwd
  if in_cwd == nil then in_cwd = true end

  local fresh = opts.bang
  for _, arg in pairs(args) do
    if arg == 'in_cwd' or arg == 'i' then in_cwd = true end
    if arg == 'all' or arg == 'a' then in_cwd = false end
    if arg == 'fresh' or arg == 'f' then fresh = true end
    if arg == 'cached' or arg == 'c' then fresh = false end
  end

  return { fresh = fresh, in_cwd = in_cwd, }
end

function M.cmd_status(opts)
  local tfvc_status = require 'tfvc.status'
  local parsed = tfvc_status.parse_cmd_args(opts)
  tfvc_status.do_with_pending_changes(parsed.fresh, function (pending_changes)
    vim.schedule(function()
      M.load_pending_changes_into_qf(pending_changes, parsed.in_cwd)
    end)
  end)
end

return M;
