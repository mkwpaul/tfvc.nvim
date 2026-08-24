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

  if #pending_changes == 0 then
    buffer_content[#buffer_content+1] = '# No pending changes'
    vim.api.nvim_set_option_value('modifiable', true, bufOpt)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_content)
    set_review_buf_opts(buf)
    return
  end

  -- Create a mapping of line number to full path
  local line_to_path = {}
  local current_line = #buffer_content + 1 -- Start after header

  -- Get expanded diffs from buffer variable (persists across re-renders)
  local expanded_diffs = vim.b[buf].tfvc_review_expanded_diffs or {}

  -- Group by change type
  ---@type table<string, tfvc.pending_change[]>
  local change_groups = {}
  for _, change in ipairs(pending_changes) do
    local change_type = change.Change or 'Unknown'
    if not change_groups[change_type] then
      change_groups[change_type] = {}
    end
    table.insert(change_groups[change_type], change)
  end

  -- Render each group
  for change_type, changes in pairs(change_groups) do
    local icon = u.change_type_to_icons(change_type)
    buffer_content[#buffer_content+1] = '## ' .. icon .. ' ' .. change_type .. ' (' .. #changes .. ')'
    current_line = current_line + 1
    buffer_content[#buffer_content+1] = ''
    current_line = current_line + 1

    for _, change in ipairs(changes) do
      local full_path = change.Relative
      local display_path = full_path
      -- Try to show relative path from cwd
      local cwd = vim.uv.cwd()
      if cwd and display_path:sub(1, #cwd) == cwd then
        display_path = display_path:sub(#cwd + 2) -- +2 to skip the path separator
      end
      buffer_content[#buffer_content+1] = icon .. ' ' .. display_path

      -- Store the mapping of line number to full path
      line_to_path[current_line] = full_path
      current_line = current_line + 1

      -- If this file's diff is expanded, insert it here
      if expanded_diffs[full_path] then
        local diff_lines = expanded_diffs[full_path]
        for _, line in ipairs(diff_lines) do
          buffer_content[#buffer_content+1] = line
          current_line = current_line + 1
        end
      end
    end
    buffer_content[#buffer_content+1] = ''
    current_line = current_line + 1
  end

  -- Store the mapping in buffer variable
  vim.b[buf].tfvc_review_line_to_path = line_to_path

  vim.api.nvim_set_option_value('modifiable', true, bufOpt)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_content)
  set_review_buf_opts(buf)

end

--- Gets the file path from the current line
---@param buf number
---@return string|nil path The file path or nil if not on a file line
local function get_file_from_line(buf)
  local line_to_path = vim.b[buf].tfvc_review_line_to_path
  if not line_to_path then
    return nil
  end

  local line_num = vim.api.nvim_win_get_cursor(0)[1] -- Get current line number (1-indexed)
  local path = line_to_path[line_num] -- Look up the path for this line
  if path then
    return vim.fs.normalize(path)
  end
  return nil
end

--- Gets the file path by searching backwards for the nearest file entry line
---@param buf number
---@return string|nil path The file path or nil if not found
local function get_file_from_line_or_above(buf)
  -- Get the line-to-path mapping from buffer variable
  local line_to_path = vim.b[buf].tfvc_review_line_to_path
  assert(not vim.isnil(line_to_path), 'tfvc_review_line_to_path must be set')

  -- Get current line number (1-indexed)
  local line_num = vim.api.nvim_win_get_cursor(0)[1]

  -- Search backwards from current line to find a file entry
  for i = line_num, 1, -1 do
    local path = line_to_path[i]
    if not vim.isnil(path) then
      return vim.fs.normalize(path)
    end
  end

  return nil
end

--- Finds the line number for a given file path
---@param buf number
---@param target_path string
---@return number|nil line_num The line number (1-indexed) or nil if not found
local function find_line_for_path(buf, target_path)
  local line_to_path = vim.b[buf].tfvc_review_line_to_path
  if not line_to_path then
    return nil
  end

  local normalized_target = vim.fs.normalize(target_path)

  for line_num, path in pairs(line_to_path) do
    if not vim.isnil(path) and vim.fs.normalize(path) == normalized_target then
      return line_num
    end
  end

  return nil
end

--- Sets up keymaps for the review buffer
---@param buf number
---@param pending_changes table
local function setup_keymaps(buf, pending_changes)
  local map = mapbuf(buf)
  local u = require('tfvc.utils')

  local function show_inline_diff(path, expanded_diffs)

    local diff_cmd = { 'diff', path, '/Format:Unified', '/noprompt' }

    u.tf_cmd(diff_cmd, { suppress_echo = true }, vim.schedule_wrap(function(obj)
      if obj.code == 0 and obj.stdout and #obj.stdout > 0 then
        local diff_lines = vim.split(obj.stdout, '\r\n')

        -- Filter out redundant header lines
        local filtered_lines = {}
        for _, line in ipairs(diff_lines) do

          -- Skip the "edit:", "File:", and first "===" separator lines
          if not (line:match('^edit:') or
                  line:match('^File:') or
                  line:match('^--- Server:') or
                  line:match('^+++ Local:') or
                  (line:match('^=+$') --[[and #filtered_lines == 0]])
                    ) then
            table.insert(filtered_lines, line)
          end
        end

        -- Remove empty last line if present
        if filtered_lines[#filtered_lines] == '' then
          table.remove(filtered_lines, #filtered_lines)
        end

        expanded_diffs[path] = filtered_lines
        vim.b[buf].tfvc_review_expanded_diffs = expanded_diffs
        render_review_buffer(buf, pending_changes)
        setup_keymaps(buf, pending_changes)
      else
        vim.notify('No diff available for this file', vim.log.levels.INFO)
      end
    end))
  end

  map('n', 'g?', '<cmd>map <buffer><CR>',  'Show Keymaps')
  map('n', 'r', 'e!', 'Refresh pending changes')

  -- Expand inline diff for file under cursor
  map('n', '>', function()
    local path = get_file_from_line(buf)
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end

    local expanded_diffs = vim.b[buf].tfvc_review_expanded_diffs or {}
    if expanded_diffs[path] then
      vim.notify('Diff already expanded', vim.log.levels.INFO)
      return
    end
    show_inline_diff(path, expanded_diffs)
  end, 'Expand inline diff for file')

  -- Collapse inline diff - works on file line or inside expanded diff
  map('n', '<', function()
    -- Try to find file from current line or search upwards
    local path = get_file_from_line_or_above(buf)
    if not path then
      vim.notify('No file found', vim.log.levels.WARN)
      return
    end

    -- Get or initialize expanded diffs table
    local expanded_diffs = vim.b[buf].tfvc_review_expanded_diffs or {}
    if not expanded_diffs[path] then
      vim.notify('Diff not expanded', vim.log.levels.INFO)
      return
    end

    -- Collapse - remove the diff
    expanded_diffs[path] = nil
    vim.b[buf].tfvc_review_expanded_diffs = expanded_diffs
    render_review_buffer(buf, pending_changes)
    setup_keymaps(buf, pending_changes)

    -- Move cursor to the file entry line
    local file_line = find_line_for_path(buf, path)
    if file_line then
      vim.api.nvim_win_set_cursor(0, {file_line, 0})
    end
  end, 'Collapse inline diff for file')

  -- Toggle inline diff for file under cursor
  map('n', '=', function()
    local path = get_file_from_line(buf)
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end

    -- Get or initialize expanded diffs table
    local expanded_diffs = vim.b[buf].tfvc_review_expanded_diffs or {}

    -- Toggle: if already expanded, collapse it; otherwise expand it
    if expanded_diffs[path] then
      -- Collapse - remove the diff
      expanded_diffs[path] = nil
      vim.b[buf].tfvc_review_expanded_diffs = expanded_diffs
      render_review_buffer(buf, pending_changes)
      setup_keymaps(buf, pending_changes)

      -- Move cursor to the file entry line
      local file_line = find_line_for_path(buf, path)
      if file_line then
        vim.api.nvim_win_set_cursor(0, {file_line, 0})
      end
    else
      show_inline_diff(path, expanded_diffs)
    end
  end, 'Toggle inline diff for file')

  -- Open diff split (compare server version with local)
  local function open_diff()
    local path = get_file_from_line(buf)
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end
    -- Compare latest server version (T) with local file
    u.diff_files(
      'tfvc:///files/T/' .. path,
      path
    )
  end
  map('n', '<CR>', open_diff, 'Open diff split')
  map('n', 'd', open_diff, 'Open diff split')

  -- Open local file
  map('n', 'gf', function()
    local path = get_file_from_line(buf)
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end
    vim.cmd('e ' .. vim.fn.fnameescape(path))
  end, 'Open local file')


  if DEBUG then
    map('n', '?', function()
      local path = get_file_from_line_or_above(buf)
      if not path then
        vim.notify('No file under cursor', vim.log.levels.WARN)
      else
        vim.notify(vim.inspect(path), vim.log.levels.INFO)
      end
    end, '')
  end

  -- Undo checkout
  map('n', 'u', function()
    local path = get_file_from_line(buf)
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end

    vim.ui.input({ prompt = 'Undo checkout of ' .. vim.fn.fnamemodify(path, ':t') .. '? (y/N): ' }, function(input)
      if input and (input:lower() == 'y' or input:lower() == 'yes') then
        local cmd = { 'undo', path, '/noprompt' }
        u.tf_cmd(cmd, { print_stdout = true }, function(obj)
          if obj.code == 0 then
            vim.schedule(function()
              vim.cmd('e!') -- Refresh
            end)
          end
        end)
      end
    end)
  end, 'Undo checkout of file')

  -- Checkin
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
    setup_keymaps(buf, pending_changes)

    -- Position cursor at first file entry
    vim.api.nvim_buf_call(buf, function()
      vim.cmd('normal! gg')
      vim.fn.search('^[^ #]') -- Find first line that doesn't start with space or #
    end)
  end))
end

return M
