local u = require('tfvc.utils')
local s = require('tfvc.state')
local xmlparser = require('tfvc.xmlparser')

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
  u.tf_cmd ({ 'status', '/format:xml' }, function(obj)
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

local function changeTypeToIcons(change)
  local words = vim.split(change, ' ', { plain=true, trimempty=true})
  local result = {}
  for _, value in pairs(words) do
    if value == "Add" then
      table.insert(result, "+")
    end
    if value == "Edit" then
      table.insert(result, "✎")
    end
    if value == "Delete" then
      table.insert(result, "␡")
    end
    if value == "Encoding" then
      table.insert(result, "🗎")
    end
  end

  return table.concat(result, " ")
end

---@param in_cwd boolean filter pending changes to only those within the current workspace
---@param pending_changes table<pendingChange>
local show_telescope_finder_impl = function(pending_changes, in_cwd, opts)
  local finders = require "telescope.finders"
  local action = require "telescope.actions"
  local tl_state = require "telescope.actions.state"
  local conf = require("telescope.config").values

  opts = opts or {}
  if in_cwd then
    pending_changes = vim.tbl_filter(function(change) return u.is_within_workspace(change.Local) end, pending_changes)
  end

  local init_mappings = function(_, map)
    map("i", "<CR>", action.file_edit)
    -- TODO get revert changes working
    map("i", "<C-u>", function(_)
      ---@type pendingChange
      local selected = tl_state.get_selected_entry()

      local choice = vim.fn.input ({prompt =  "Undo PendingChanges in " .. selected.name .. "? (y/n)",  default = 'y', cancelreturn = 'n' })
      if choice == 'y' then
        local tfvc = require('tfvc.tfvc')
        tfvc.tf_undo(nil, selected.Local)
      end
    end)
  end

  ---@param entry pendingChange
  local entry_maker = function(entry)
    local path = u.get_local_path_relative(entry.Local)
    local display = path .. " " .. changeTypeToIcons(entry.Change)
    return {
      value = entry,
      display = display,
      ordinal = entry.item,
      path = path,
    }
  end

  local def = {
    prompt_title = "PendingChanges",
    finder = finders.new_table {
      results = pending_changes,
      entry_maker = entry_maker,
      attach_mappings =  init_mappings,
    },
    sorter = conf.generic_sorter(opts),
    previewer = conf.file_previewer(opts),
  }

  local pickers = require "telescope.pickers"
  local themes = require "telescope.themes"

  pickers.new(themes.get_ivy(opts), def):find()
end

---@param fresh boolean force requery. don't display from cache
---@param in_cwd boolean filter by current working directory
---@param opts table
function M.show_telescope_finder(fresh, in_cwd, opts)
  opts = opts or {}
  M.do_with_pending_changes(fresh, function (pending_changes)
    vim.schedule(function()
      show_telescope_finder_impl(pending_changes, in_cwd, opts)
    end)
  end)
end

function M.load_pending_changes_into_qf(fresh, in_cwd)
  M.do_with_pending_changes(fresh, function (pending_changes)

    vim.schedule(function()
      if in_cwd then
        pending_changes = vim.tbl_filter(function(change) return u.is_within_workspace(change.Local) end, pending_changes)
      end
      local qf_entries = vim.tbl_map(function (change)
        return {
          filename = change.Local,
          valid = true,
          text = change.name,
        }
      end, pending_changes)

      vim.fn.setqflist(qf_entries)
      vim.cmd.copen()

      --[[
      vim.diagnostic.setqflist({
        items = qf_entries,
        title = "tfvc: pending changes",
        open = true,
      })
      ]]
    end)
  end)
end

---@param opts cmd_call_args
function M.cmd_show_telescope_finder(opts)
  local args = opts.fargs or {}
  local in_cwd = vim.g.tf_filter_outside_cwd
  if in_cwd == nil then
    in_cwd = true
  end
  local fresh = opts.bang

  if #args == 0 then
    M.show_telescope_finder_cached(fresh, in_cwd, opts)
    return
  end
  for _, arg in pairs(args) do
    if arg == 'in_cwd' or arg == 'i' then
      in_cwd = true
    end
    if arg == 'all' or arg == 'a' then
      in_cwd = false
    end
    if arg == 'fresh' or arg == 'f' then
      fresh = true
    end
    if arg == 'cached' or arg == 'c' then
      fresh = false
    end
  end
  M.show_telescope_finder(fresh, in_cwd, opts)
end

return M;
