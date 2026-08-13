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
---@param show_inline_diff boolean
local function render_review_buffer(buf, pending_changes, show_inline_diff)
  local bufOpt = { buf = buf }
  local u = require('tfvc.utils')
  local v = require('tfvc.options')

  local buffer_content = {
    '# TFVC Review - Pending Changes',
    '# Help: g? for keymaps',
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
      buffer_content[#buffer_content+1] = '  ' .. icon .. ' ' .. display_path

      -- Store the mapping of line number to full path
      line_to_path[current_line] = full_path
      current_line = current_line + 1
    end
    buffer_content[#buffer_content+1] = ''
    current_line = current_line + 1
  end

  -- Store the mapping in buffer variable
  vim.b[buf].tfvc_review_line_to_path = line_to_path

  -- Add inline diff if requested
  if show_inline_diff then
    buffer_content[#buffer_content+1] = '---'
    buffer_content[#buffer_content+1] = '# Inline Diff'
    buffer_content[#buffer_content+1] = ''

    -- Get unified diff
    local diff_cmd = {
      'diff',
      vim.uv.cwd() or '.',
      '/Format:Unified',
      '/recursive',
      '/ignorecase',
      '/ignorespace',
      '/noprompt'
    }

    u.tf_cmd(diff_cmd, { suppress_echo = true }, vim.schedule_wrap(function(obj)
      if obj.code == 0 and obj.stdout and #obj.stdout > 0 then
        local diff_lines = vim.split(obj.stdout, '\r\n')
        vim.api.nvim_set_option_value('modifiable', true, bufOpt)
        vim.list_extend(buffer_content, diff_lines)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_content)
        set_review_buf_opts(buf)

        -- Position cursor at first file entry
        vim.api.nvim_buf_call(buf, function()
          vim.cmd('normal! gg')
          vim.fn.search('^  ')
        end)
      end
    end))
  end

  vim.api.nvim_set_option_value('modifiable', true, bufOpt)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_content)
  set_review_buf_opts(buf)

  if not show_inline_diff then
    -- Position cursor at first file entry
    vim.api.nvim_buf_call(buf, function()
      vim.cmd('normal! gg')
      vim.fn.search('^  ')
    end)
  end
end

--- Gets the file path from the current line
---@param buf number
---@return string|nil path The file path or nil if not on a file line
local function get_file_from_line(buf)
  -- Get the line-to-path mapping from buffer variable
  local line_to_path = vim.b[buf].tfvc_review_line_to_path
  if not line_to_path then
    return nil
  end

  -- Get current line number (1-indexed)
  local line_num = vim.api.nvim_win_get_cursor(0)[1]

  -- Look up the path for this line
  local path = line_to_path[line_num]

  if path then
    return vim.fs.normalize(path)
  end

  return nil
end

--- Sets up keymaps for the review buffer
---@param buf number
---@param pending_changes table
local function setup_keymaps(buf, pending_changes)
  local map = mapbuf(buf)
  local u = require('tfvc.utils')

  -- Help
  map('n', 'g?', function()
    local help = {
      'TFVC Review Keymaps:',
      '',
      '  g?        - Show this help',
      '  q         - Close review buffer',
      '  r         - Refresh pending changes',
      '  i         - Toggle inline diff view',
      '',
      '  <CR>      - Open diff split for file under cursor',
      '  d         - Open diff split for file under cursor',
      '  gf        - Open local file under cursor',
      '  -         - Stage/unstage file (checkout for edit if needed)',
      '  u         - Undo checkout of file under cursor',
      '',
      '  cc        - Checkin pending changes',
      '',
    }
    vim.notify(table.concat(help, '\n'), vim.log.levels.INFO)
  end, 'Show Help')

  -- Close buffer
  map('n', 'q', '<cmd>close<CR>', 'Close review buffer')

  -- Refresh
  map('n', 'r', function()
    vim.cmd('e!')
  end, 'Refresh pending changes')

  -- Toggle inline diff
  map('n', 'i', function()
    local show_inline = not vim.b[buf].show_inline_diff
    vim.b[buf].show_inline_diff = show_inline
    render_review_buffer(buf, pending_changes, show_inline)
    setup_keymaps(buf, pending_changes) -- Re-setup keymaps after re-render
  end, 'Toggle inline diff')

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

  -- Checkout for edit (stage)
  map('n', '-', function()
    local path = get_file_from_line(buf)
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
      return
    end
    local cmd = { 'checkout', path }
    u.tf_cmd(cmd, { print_stdout = true }, function(obj)
      if obj.code == 0 then
        vim.schedule(function()
          vim.cmd('e!') -- Refresh
        end)
      end
    end)
  end, 'Checkout file for edit')

  map('n', '?', function()
    local path = get_file_from_line(buf)
    if not path then
      vim.notify('No file under cursor', vim.log.levels.WARN)
    else
      vim.notify(path, vim.log.levels.INFO)
    end
  end, '')

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

  -- Initialize buffer state
  if vim.b[buf].show_inline_diff == nil then
    vim.b[buf].show_inline_diff = false
  end
  local show_inline_diff = vim.b[buf].show_inline_diff

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

    -- Render the buffer
    render_review_buffer(buf, pending_changes, show_inline_diff)

    -- Setup keymaps
    setup_keymaps(buf, pending_changes)
  end))
end

return M
