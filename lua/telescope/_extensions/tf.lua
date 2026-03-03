local telescope = require 'telescope'

---@param pending_changes table<tfvc.pending_change>
local function show_telescope_finder_impl(pending_changes, opts)

  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local tfvc_opts = require ('tfvc.options')
  local tfvc_utils = require 'tfvc.utils'

  opts = opts or {}
  if tfvc_opts.filter_status_by_cwd then
    pending_changes = vim.tbl_filter(function(change)
      return tfvc_utils.is_within_workspace(change.Local)
    end, pending_changes)
  end

  ---@param entry tfvc.pending_change
  local function entry_maker(entry)
    local path = tfvc_utils.get_local_path_relative(entry.Local)
    local display = path .. " " .. tfvc_utils.change_type_to_icons(entry.Change)
    return {
      value = entry,
      display = display,
      ordinal = entry.item,
      path = path,
    }
  end

  local previewer = require ('telescope.previewers').new_buffer_previewer({
    title = "Diff",
    define_preview = function(self, entry, status)
      local cmd = {
        'diff', '/Format:Unified',
        '/ignorecase', '/ignorespace', '/noprompt',
        entry.path
      }
      tfvc_utils.tf_cmd(cmd, { suppress_echo = true}, vim.schedule_wrap(function (obj)
        local lines = vim.split(obj.stdout or obj.stderr, '\r\n')
        local bufOpt = { buf = self.state.bufnr }
        vim.api.nvim_set_option_value('filetype', 'diff', bufOpt)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end))
    end,
  })

  local def = {
    prompt_title = "Pending Changes",
    sorter = conf.generic_sorter(opts),
    previewer = previewer,
    finder = finders.new_table {
      results = pending_changes,
      entry_maker = entry_maker,
    },
  }

  local pickers = require "telescope.pickers"
  pickers.new(opts, def):find()
end

---@param opts vim.api.keyset.create_user_command.command_args
local function cmd_show_telescope_finder(opts)
  local tfvc = require 'tfvc.utils'
  tfvc.do_with_pending_changes(true, function (pending_changes)
    vim.schedule(function()
      show_telescope_finder_impl(pending_changes, opts)
    end)
  end)
end

return telescope.register_extension({
  setup = function (_, _) end,
  exports = {
    status = cmd_show_telescope_finder,
  },
})
