local telescope = require 'telescope'

---@param in_cwd boolean filter pending changes to only those within the current workspace
---@param pending_changes table<pendingChange>
local show_telescope_finder_impl = function(pending_changes, in_cwd, opts)
  local finders = require "telescope.finders"
  local action = require "telescope.actions"
  local tl_state = require "telescope.actions.state"
  local conf = require("telescope.config").values
  local u = require 'tfvc.utils'
  local tfvc_status = require 'tfvc.status'

  opts = opts or {}
  if in_cwd then
    pending_changes = vim.tbl_filter(function(change)
      return u.is_within_workspace(change.Local)
    end, pending_changes)
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
    local display = path .. " " .. tfvc_status.change_type_to_icons(entry.Change)
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

  pickers.new(opts, def):find()
end

---@param opts vim.api.keyset.create_user_command.command_args
local function cmd_show_telescope_finder(opts)
  local tfvc_status = require 'tfvc.status'
  local parsed = tfvc_status.parse_cmd_args(opts)
  tfvc_status.do_with_pending_changes(parsed.fresh, function (pending_changes)
    vim.schedule(function()
      show_telescope_finder_impl(pending_changes, parsed.in_cwd, opts)
    end)
  end)
end

return telescope.register_extension({
  setup = function (_, _)
  end,
  exports = {
    tf_status = cmd_show_telescope_finder,
  },
})
