--- Interactive review of local changes (similar to vim-fugitive's :Git)
local M = {}

local function mapbuf(buf)
  return function (modes, lhs, rhs, desc)
    vim.keymap.set(modes, lhs, rhs, { buf = buf, desc = desc })
  end
end

--- Sets buffer options for the review buffer
---@param buf number
local function set_review_buf_opts(buf)
  local bufOpt = { buf = buf }
  vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
  vim.api.nvim_set_option_value('swapfile', false, bufOpt)
  vim.api.nvim_set_option_value('modifiable', false, bufOpt)
  vim.api.nvim_set_option_value('modified', false, bufOpt)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', bufOpt)
  vim.api.nvim_set_option_value('filetype', 'tf_review', bufOpt)
  vim.api.nvim_set_option_value('buflisted', false, bufOpt)
end

--- Renders the review buffer with pending changes
---@param buf number
---@param pending_changes tfvc.pending_change[]
local function render_review_buffer(buf, pending_changes)
  local bufOpt = { buf = buf }
  local u = require('tfvc.utils')

  local buffer_content = {
    'TFVC: Status',
    'Help: g? for keymaps',
    '',
  }

  vim.api.nvim_set_option_value('modifiable', true, bufOpt)

  if #pending_changes == 0 then
    buffer_content[#buffer_content+1] = '# No pending changes'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_content)
    set_review_buf_opts(buf)
    return
  end

  for _, change in ipairs(pending_changes) do
    local full_path = change.Relative
    local display_path = full_path
    -- Try to show relative path from cwd
    local cwd = vim.uv.cwd()
    if cwd and display_path:sub(1, #cwd) == cwd then
      display_path = display_path:sub(#cwd + 2) -- +2 to skip the path separator
    end
    local icon = u.change_type_to_abbr(change.Change)
    buffer_content[#buffer_content+1] = icon .. ' ' .. display_path
  end

  buffer_content[#buffer_content+1] = ''
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_content)
  set_review_buf_opts(buf)
end

--- Gets the file path from the current line
---@return string|nil path The file path or nil if not on a file line
local function get_file_from_line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if (cursor[1] < 3) then return nil end
  local line = vim.api.nvim_get_current_line()
  if #line <= 3 then return nil end
  if line:match("^%+") or line:match("^%-") or line:match("^#") then
      return nil
  end
  return line:sub(3)
end

local function setup_keymaps(buf)
  local map = mapbuf(buf)
  local u = require('tfvc.utils')

  local bufOpt = { buf = buf }
  local ns = vim.api.nvim_create_namespace('tfvc')

  local function show_inline_diff()
    local path = get_file_from_line()
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end
    local inline_cmd = { 'diff', path, '/Format:Unified' }
    u.tf_cmd(inline_cmd, { print_stdout = false, suppress_echo = true },
    vim.schedule_wrap(function (obj)
      local diff_lines = vim.split(obj.stdout or obj.stderr, '\r\n')
      diff_lines = vim.iter(diff_lines)
      :filter(function (line)
        return not (line:match('^edit:') or
        line:match('^File:') or
        line:match('^%-%-%-') or
        line:match('^%+%+%+') or
        (line:match('^=+$') )
      )end)
      :totable()

      if diff_lines[#diff_lines] == '' then
        diff_lines[#diff_lines] = nil
      end

      local hl_group = nil -- 'IncSearch'
      if #diff_lines > 0 then
        vim.api.nvim_set_option_value('modifiable', true, bufOpt)
        local cursor = vim.api.nvim_win_get_cursor(0)
        vim.api.nvim_put(diff_lines, 'l', true, false)
        vim.api.nvim_buf_set_extmark(buf, ns, cursor[1] - 1, 0, { end_line = cursor[1] + #diff_lines, hl_group = hl_group})
        vim.api.nvim_win_set_cursor(0, cursor)
        vim.api.nvim_set_option_value('modifiable', false, bufOpt)
      end

    end))
  end

  local function del_inline_diff()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cu_row = cursor[1] - 1
    local cu_col = cursor[2]

    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    for _, mark in ipairs(marks) do
      local id = mark[1]
      local start_row = mark[2]
      local start_col = mark[3]
      local details = assert(mark[4])

      local end_row = details.end_row
      local end_col = details.end_col

      -- Check if the cursor is inside this specific block's boundaries
      local after_start = (cu_row > start_row) or (cu_row == start_row and cu_col >= start_col)
      local before_end = (cu_row < end_row) or (cu_row == end_row and cu_col <= end_col)

      if after_start and before_end then
        -- + 1 because the line of the changed file is part of the extmark region too,
        -- we don't want to delete that line
        vim.api.nvim_set_option_value('modifiable', true, bufOpt)
        vim.api.nvim_buf_set_text(0, start_row + 1, 0, end_row, end_col, {})
        vim.api.nvim_buf_del_extmark(0, ns, id)
        vim.api.nvim_set_option_value('modifiable', false, bufOpt)
        return true
      end
    end
  end

  local function open_diff()
    local path = get_file_from_line()
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end
    u.diff_files(
      'tfvc:///files/T/' .. path,
      path
    )
  end

  map('n', 'g?', '<cmd>map <buffer><CR>',  'Show Keymaps')
  map('n', '>', show_inline_diff, 'Expand inline diff for file')
  map('n', '<', del_inline_diff, 'Collapse inline diff for file')
  map('n', '=', function()
    if not del_inline_diff() then
      show_inline_diff()
    end
  end, 'Toggle inline diff for file')

  map('n', '<CR>', open_diff, 'Open diff split')
  map('n', 'd', open_diff, 'Open diff split')

  -- Open local file
  map('n', 'gf', function()
    local path = get_file_from_line()
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end
    vim.cmd('e ' .. vim.fn.fnameescape(path))
  end, 'Open local file')

  -- Undo checkout
  map('n', 'X', function()
    local path = get_file_from_line()
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end

    if vim.fn.confirm('Undo checkout of ' .. vim.fn.fnamemodify(path, ':t') .. '?') == 1 then
      local cmd = { 'undo', path, '/noprompt' }
      u.tf_cmd(cmd, { print_stdout = true }, function(obj)
        if obj.code == 0 then
          vim.schedule(function()
            vim.cmd('e!') -- Refresh
          end)
        end
      end)
    end
  end, 'Undo checkout of file')

  -- Checkin
  --[[
  map('n', 'cc', function()
    -- Get all pending files
    local files = {}
    for _, change in ipairs(pending_changes) do
      table.insert(files, change.name)
    end

    if #files == 0 then
      vim.notify('No pending changes to checkin', vim.log.levels.WARN)
      return
    end

    vim.ui.input({ prompt = 'Checkin comment: ' }, function(comment)
      if comment and #comment > 0 then
        local cmd = { 'checkin', '/comment:' .. comment, '/noprompt' }
        vim.list_extend(cmd, files)
        u.tf_cmd(cmd, { print_stdout = true }, function(obj)
          if obj.code == 0 then
            vim.schedule(function()
              vim.cmd('e!') -- Refresh
            end)
          end
        end)
      end
    end)
  end, 'Checkin pending changes')
  ]]
end

--- Main entry point for the review buffer
---@param args table
function M.review_bufreadcmd(args)
  local buf = args.buf
  local u = require('tfvc.utils')

  -- Get pending changes
  local fresh = true
  u.do_with_pending_changes(fresh, vim.schedule_wrap(function(pending_changes)
    -- Filter by cwd if option is set
    local v = require('tfvc.options')
    local in_cwd = v.filter_status_by_cwd
    if in_cwd then
      local cwd = vim.uv.cwd()
      if cwd then
        local filtered = {}
        for _, change in ipairs(pending_changes) do
          if change.name:sub(1, #cwd) == cwd then
            table.insert(filtered, change)
          end
        end
        pending_changes = filtered
      end
    end

    render_review_buffer(buf, pending_changes)
    setup_keymaps(buf)

    -- Position cursor at first file entry
    vim.api.nvim_buf_call(buf, function() vim.cmd('4') end)
  end))
end

return M
