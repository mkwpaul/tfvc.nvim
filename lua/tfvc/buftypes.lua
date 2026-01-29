--- implements reading logic and keyhandling for custom tfvc:/// buffers
local M = {}

local function get_changeset_web_url(changeset)
  local vars = require('tfvc.options')
  local header = vars.version_control_web_url .. '/changeset/'.. changeset
  return header
end

--- tries to read the changeset number from the current line,
--- when called during visual mode, returns both the changeset numbers of the ends of the selection
--- returns nil (or nil, nil) if the corresponding line has no changeset number
---@param buf number
local function history_buf__get_changeset_from_line(buf)
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'v' or mode == 'V' then

    -- vim.api.nvim_buf_get_mark(_, '<') doesn't update until visual mode exists
    -- fn.getpos apparently is the most reliable way to get the start and end lines of the current visual selection
    -- also: mixed 0 and 1 based indexing is fucking hell...
    -- this returns 1-based linenumbers... (like what is shown in the editor as linenumber)
    local s = vim.fn.getpos('v')[2]
    local e = vim.fn.getpos('.')[2]

    -- ...but this takes 0-based line numbers, hence range of [x-1..x) [inclusive-start, exclusive-end)
    local start = vim.api.nvim_buf_get_lines(buf, s-1, s, true)
    local eend = vim.api.nvim_buf_get_lines(buf, e-1, e, true)

    -- but arrays always are 1-indexed
    local cs_start = start[1]:gmatch('%d+')()
    local cs_end = eend[1]:gmatch('%d+')()

    -- lower end always first
    -- split-layout should not depend on what end of the selection the cursor was on
    if cs_start > cs_end then
      return cs_end, cs_start
    else
      return cs_start, cs_end
    end
  else
    local line = vim.api.nvim_get_current_line()
    local cs_number = line:gmatch('%d+')()
    return cs_number
  end
end

---@type tf_cmd_opts
local tfcmdOpts = {
  suppress_echo = true,
  return_stderr_on_failure = true,
  debug = true,
}

function M.history_callback(args)
  local buf = args.buf
  local bufOpt = { buf = buf }

  -- tell neovim that this buffer is now read-only and modifiable by us
  vim.api.nvim_set_option_value('modifiable', true, bufOpt)
  vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
  vim.api.nvim_set_option_value('swapfile', false, bufOpt)

  local vars = require('tfvc.options')

  local path = args.file:gsub('tfvc:///history/', '') or '.'
  local limit = vars.history_entry_limit
  local cmd = { 'history',  path, '/recursive', '/noprompt', '/stopafter:'..limit, '/format:brief' }
  local u = require('tfvc.utils')
  u.tf_cmd(cmd, tfcmdOpts, vim.schedule_wrap(function(obj)
    -- Replace buffer content with command output
    vim.api.nvim_set_option_value('filetype', 'tf_history', bufOpt)
    vim.api.nvim_set_option_value('ff', 'dos', bufOpt)
    local output = obj.stdout or obj.stderr
    local lines = vim.split(output, '\r\n')
    local fsinfo =  vim.uv.fs_stat(path)

    table.insert(lines, 1, '# History (' .. fsinfo.type ..')')
    table.insert(lines, 2, '# Local-Path: ' .. path)
    table.insert(lines, 3, "# Keymaps:")
    table.insert(lines, 4, "#  n:  'gd': View changeset")
    table.insert(lines, 5, "#  n:  'gx': Open link to changeset in browser")
    if fsinfo.type == 'file' then
      table.insert(lines, 6, "#  n:  'gf': View version")
      table.insert(lines, 7, "#  n:  'dl': Compare version with local file")
      table.insert(lines, 8, "#  v:  'd':  Compare versions based on the start, and end of the visual selection ")
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)
    vim.api.nvim_set_option_value('modified', false, bufOpt)

    -- keymaps
    local function open_cs()
      local cs_number = history_buf__get_changeset_from_line(buf)
      if cs_number then
        vim.cmd('e tfvc:///changeset/'..cs_number )
      end
    end

    local keymapOpt = { buffer = buf }

    if fsinfo.type == 'file' then

      vim.keymap.set('n', 'gf', function ()
        local cs_number = history_buf__get_changeset_from_line(buf)
        if cs_number then
          vim.cmd('e tfvc:///files/C' .. cs_number .. '/' .. path)
        end
      end, keymapOpt)

      vim.keymap.set('v', 'd', function ()
        local cs_start, cs_end = history_buf__get_changeset_from_line(buf)
        if not cs_start or not cs_end then
          return
        end
        require('tfvc.utils').close_tfvc_diff_wins()
        vim.cmd.diffoff({ bang = true })
        vim.cmd.edit('tfvc:///files/C' .. cs_start .. '/' .. path)
        vim.cmd.diffsplit('tfvc:///files/C' .. cs_end .. '/' .. path)
      end, keymapOpt)
      vim.keymap.set('n', 'dl', function ()


        local cs = history_buf__get_changeset_from_line(buf)
        if not cs then
          return
        end
        require('tfvc.utils').close_tfvc_diff_wins()
        vim.cmd.diffoff({ bang = true })
        vim.cmd.edit(path)
        vim.cmd.diffsplit('tfvc:///files/C' .. cs .. '/' .. path)
      end, keymapOpt)
    end

    vim.keymap.set('n', '<CR>', open_cs, keymapOpt)
    vim.keymap.set('n', 'gd', open_cs, keymapOpt)
    vim.keymap.set('n', 'gx', function ()
      local line = vim.api.nvim_get_current_line()
      local cs_number = line:gmatch('%d+')()
      if cs_number then
        vim.ui.open(get_changeset_web_url(cs_number));
      end
    end, keymapOpt)
  end))
end

-- basically the same as above, only we call a different tf command + no custom keymap
function M.changeset_callback (args)
  local buf = args.buf
  local bufOpt = { buf = buf }

  -- tell neovim that this buffer is now read-only and modifiable by us
  vim.api.nvim_set_option_value('modifiable', true, bufOpt)
  vim.api.nvim_set_option_value('swapfile', false, bufOpt)
  vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)

  local cs = args.file:gsub('tfvc:///changeset/', '')
  local cmd = { 'changeset', cs, '/noprompt',  }

  local u = require('tfvc.utils')
  u.tf_cmd(cmd, tfcmdOpts, vim.schedule_wrap(function(obj)
    -- Replace buffer content with command output
    vim.api.nvim_set_option_value('filetype', 'tf_changeset', bufOpt)
    vim.api.nvim_set_option_value('ff', 'dos', bufOpt)
    local output = obj.stdout or obj.stderr
    local lines = vim.split(output, '\r\n')
    local header = get_changeset_web_url(cs)
    table.insert(lines, 1, header);
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)
    vim.api.nvim_set_option_value('modified', false, bufOpt)
  end))
end

function M.files_callback(args)
  local buf = args.buf
  local bufOpt = { buf = buf }

  vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
  vim.api.nvim_set_option_value('modifiable', true, bufOpt)
  vim.api.nvim_set_option_value('swapfile', false, bufOpt)

  local path = args.file:gsub('tfvc:///files/', '')
  local versionspec = 'T'
  local idx = path:find('/', 0, true)
  if idx then
    versionspec = path:sub(1, idx - 1)
    path = path:sub(idx + 1, nil)
  end

  local u = require 'tfvc.utils'
  local fresh = vim.v.cmdbang == 1
  u.tf_get_version_from_versionspec(path, versionspec, fresh, function (file_path)
    -- local lines = vim.fn.readfile(file_path)
    -- vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd('noautocmd keepalt keepjumps silent read ++edit ' .. vim.fn.fnameescape(file_path))
      vim.api.nvim_buf_set_lines(buf, 0, 1, true, {}); -- replace first line with no lines (i.e. delete first line)
    end)
    -- must detect filetype before setting filetype
    vim.cmd [[ filetype detect ]]
    vim.api.nvim_set_option_value('modified', false, bufOpt)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)

    vim.b[buf].versionspec = versionspec
    vim.b[buf].local_path = path
    vim.b[buf].is_server_file = true
  end)
end

return M
