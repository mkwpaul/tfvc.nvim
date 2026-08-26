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
local function get_file_from_line(row)
  row = row or vim.api.nvim_win_get_cursor(0)[1]
  if (row < 3) then return nil end
  local lines = vim.api.nvim_buf_get_lines(0, row - 1, row, false)
  local line = lines[1]
  if #line <= 3 then return nil end
  if line:match("^%+") or line:match("^%-") or line:match("^#") then
      return nil
  end
  return line:sub(3)
end

local function show_inline_diff(buf, row, replace)
  local u = require('tfvc.utils')
  coroutine.wrap(function ()
    row = row or vim.api.nvim_win_get_cursor(0)[1]
    local path = get_file_from_line(row)
    if not path then
      return
    end
    local mark = u.get_mark_under_cursor()
    if mark and not replace then
      return
    end
    if replace then
      u.inline_diff.del(buf, mark)
    end

    local diff = u.get_file_diff_co(path, 'T', 'L')
    u.inline_diff.insert(diff.stdout or diff.stderr, buf, row)
  end)()
end

local function setup_keymaps(buf)
  local map = mapbuf(buf)
  local u = require('tfvc.utils')

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

  local function del_inline_diff()
    return u.inline_diff.del(buf)
  end

  map('n', 'g?', '<cmd>map <buffer><CR>',  'Show Keymaps')
  map('n', '>', function() show_inline_diff(buf, nil, nil) end, 'Expand inline diff for file')
  map('n', '<', u.inline_diff.del, 'Collapse inline diff for file')
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

    -- vim.api.nvim_create_autocmd('BufEnter', {
    --   buf = buf,
    --   callback = vim.schedule_wrap(function(args)
    --     local marks = vim.api.nvim_buf_get_extmarks(0, u.ns, 0, -1, { details = true })
    --     for _, value in pairs(marks) do
    --       show_inline_diff(buf,  value[2] + 1, true)
    --     end
    --   end)
    -- })

  end))
end

return M
