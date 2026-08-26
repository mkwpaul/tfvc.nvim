--- implements 'rendering' logic and keyhandling for custom tfvc:/// buffers
local M = {}

local function mapbuf(buf)
  return function (modes, lhs, rhs, desc)
    vim.keymap.set(modes, lhs, rhs, { buf = buf, desc = desc })
  end
end

function M.set_tfvc_buf_opts(buf, delete)
  local bufOpt = { buf = buf }
  vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
  vim.api.nvim_set_option_value('swapfile', false, bufOpt)
  vim.api.nvim_set_option_value('modifiable', false, bufOpt)
  vim.api.nvim_set_option_value('modified', false, bufOpt)
  if delete then
    -- delete to clean up after ourselves...
    -- debatable whether this is needed or not
    -- but we're caching the files for changesets and server-files
    -- anyway so reloading them is fast anyway.
    vim.api.nvim_set_option_value('bufhidden', 'delete', bufOpt)
  end
end

vim.api.nvim_create_autocmd('BufEnter', {
  pattern = 'tfvc:///*',
  callback = function (args)
    --
    -- unlist buffers to not clutter the buffer list
    --
    -- 'buflisted' is reset each time a buffer is opened with :edit (and similar commands)
    -- therefore we need to unlist our buffers everytime we enter them
    vim.api.nvim_set_option_value('buflisted', false, { buf = args.buf })
  end,
})

--- tries to read the changeset number from the current line,
--- when called during visual mode, returns both the changeset numbers of the ends of the selection
--- returns nil (or nil, nil) if the corresponding line has no changeset number
---@param buf number
function M.history___get_changeset_from_line(buf)
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

function M.history_bufreadcmd(args)
  local buf = args.buf
  local bufOpt = { buf = buf }
  local vars = require('tfvc.options')
  local path = args.file:gsub('tfvc:///history/', '')
  if path == '' or path == '.' or path == './' then
    path = assert(vim.uv.cwd())
  end

  local normalized = vim.fs.normalize(path)
  if normalized ~= path then
    vim.schedule(function ()
      vim.print('redirected to normalized: ' .. normalized)
      vim.cmd.edit('tfvc:///history/'..normalized)
    end)
    vim.api.nvim_buf_delete(args.buf, { force = true })
    return
  end

  vim.api.nvim_set_option_value('modifiable', true, bufOpt)
  local limit = vars.history_entry_limit
  local cmd = { 'history',  path,  '/noprompt', '/stopafter:'..limit, '/format:brief',  }
  local u = require('tfvc.utils')

  local fsinfo =  vim.uv.fs_stat(path) or { type = 'unknown' }

  -- The /itemmode flag changes how the TF tool tracks history by considering a files identity rather than its location
  -- Practically this means that we get to see the history past a rename / move.
  --
  -- '/itemmode' and '/recursive' are mutually exclusive however.
  --
  -- If /recursive is set, then itemmode gets ignored.
  -- So we set one or the other
  -- if fsinfo.type == 'file' then
  --   table.insert(cmd, '/itemmode')
  -- else
  -- end
  table.insert(cmd, '/recursive')


  ---@type string|nil
  local continue_at = nil

  local __load_more_prompt = '<C-l> to load more history'
  local buffer_contents = {
    '# TFVC-History (' .. fsinfo.type ..')',
    '# Local-Path: ' .. path,
    "# Help: g?",
    __load_more_prompt
  }

  ---@type tfvc.tf_cmd_opts
  local tf_cmd_opts = {
    suppress_echo = true,
    return_stderr_on_failure = true,
  }

  local function render_page(obj, remove_header)
    local lines = vim.split(obj.stdout or obj.stderr, '\r\n')
    table.remove(lines, #lines) -- removes last blank line
    if remove_header then
      table.remove(lines, 1) -- removes column headers
      table.remove(lines, 1) -- removes separator line
      table.remove(lines, 1) -- removes first entry, which we already have
    end

    table.remove(buffer_contents, #buffer_contents) -- removes load more prompt
    vim.list_extend(buffer_contents, lines) -- adds newly fetched history

    if #lines > (vars.history_entry_limit - 5) then
      continue_at = lines[#lines]:gmatch('%d+')()
      buffer_contents[#buffer_contents+1] = __load_more_prompt
    else
      continue_at = nil
    end
    vim.api.nvim_set_option_value('modifiable', true, bufOpt)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_contents)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)
  end

  local _cmd = vim.tbl_extend('error', cmd, {})
  u.tf_cmd(_cmd, tf_cmd_opts, vim.schedule_wrap(function(obj)
    -- Replace buffer content with command output
    vim.api.nvim_set_option_value('filetype', 'tf_history', bufOpt)
    vim.api.nvim_set_option_value('ff', 'dos', bufOpt)

    M.set_tfvc_buf_opts(buf)
    render_page(obj, false)

    -- move cursor to first changed file
    vim.api.nvim_buf_call(buf, function()
      local goto_content = ':' .. (6)
      vim.cmd(goto_content)
    end)

    --- keymaps
    ---
    ---@param cb fun(cs1:string,cs2:string?)
    ---@return fun() function
    local function with_cs_do(cb)
      return function ()
        local cs1, cs2 = M.history___get_changeset_from_line(buf)
        if cs1 then cb(cs1, cs2) end
      end
    end
    local open_cs = with_cs_do(function (cs1)
      vim.cmd('e tfvc:///changeset/'..cs1)
    end)
    local view_cs_file_version = with_cs_do(function (cs1)
      vim.cmd('e tfvc:///files/C' .. cs1 .. '/' .. path)
    end)
    local comp_via_visual = with_cs_do(function (cs1, cs2)
      u.diff_files(
       'tfvc:///files/C' .. cs1 .. '/' .. path,
       'tfvc:///files/C' .. cs2 .. '/' .. path)
    end)
    local compare_with_local = with_cs_do(function (cs1)
      u.diff_files(
        'tfvc:///files/C' .. cs1 .. '/' .. path,
        path)
    end)
    local open_cs_in_web = with_cs_do(function (cs1)
      vim.ui.open(u.get_changeset_web_url(cs1));
    end)

    local function load_more()
      if not continue_at then
        print('no more to load')
        return
      end
      local cmd_load_more = { unpack(cmd) }
      cmd_load_more[#cmd_load_more+1] = '/v:' .. continue_at
      u.tf_cmd(cmd_load_more, tf_cmd_opts, vim.schedule_wrap(function(obj2)
        render_page(obj2, true)
      end))
    end

    local map = mapbuf(buf);
    map('n', 'g?', '<cmd>map <buffer><CR>', 'Show Help')
    map('n', 'gx', open_cs_in_web, 'Open changeset in web client')
    map('n', 'dd', open_cs, 'Open Changeset')
    map('n', '<CR>', open_cs,' Open Changeset')
    map('n', '<C-l>', load_more, 'Load More')

    map('n', '<leader>te', '<cmd>e '.. path .. '<CR>', 'Go to local file')
    if fsinfo.type == 'file' then
      map('n', 'gf', view_cs_file_version, 'View Changeset File version')
      map('n', 'dl', compare_with_local, 'Compare with local')
      map('v', 'dd', comp_via_visual, 'Compare with local (stard-end based on selection')
      map('v', '<CR>', comp_via_visual, 'Compare with local (stard-end based on selection')
    end
  end))
end

function M.changeset_bufreadcmd(args)
  local buf = args.buf
  local bufOpt = { buf = buf }

  local cs = args.file:gsub('tfvc:///changeset/', '')
  local cmd = { 'changeset', cs, '/noprompt',  }

  ---@type tfvc.tf_cmd_opts
  local tf_cmd_opts = {
    suppress_echo = true,
    return_stderr_on_failure = true,
    memoize = true,
  }

  local u = require('tfvc.utils')
  u.tf_cmd(cmd, tf_cmd_opts, vim.schedule_wrap(function(obj)

    -- Replace buffer content with command output
    vim.api.nvim_set_option_value('modifiable', true, bufOpt)
    vim.api.nvim_set_option_value('filetype', 'tf_changeset', bufOpt)
    vim.api.nvim_set_option_value('ff', 'dos', bufOpt)

    local buffer_content = {
      '# TFVC-Changeset: ' .. cs,
      '# Web-Url: ' .. u.get_changeset_web_url(cs),
      '# Help: g?',
    }

    local lines = vim.split(assert(obj.stdout or obj.stderr), '\r\n', { plain = true })
    table.remove(lines, 1) -- remove first line "Changeset: 144139" we already have a line like that in our header
    vim.list_extend(buffer_content, lines)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_content)
    M.set_tfvc_buf_opts(buf, true)

    -- move cursor to first changed file
    vim.api.nvim_buf_call(buf, function()
      vim.cmd '/\\$'
      vim.cmd.nohlsearch()
    end)

    --- keymaps
    ---@param cb fun(path:string)
    local function with_path_do(cb)
      return function ()
        local line = vim.api.nvim_get_current_line()
        local path, sub_count = line:gsub('.* %$', '$')
        if sub_count ~= 1 then return end
        path = u.server_path_to_local_path(path, true)
        if path then
          cb(path)
        end
      end
    end

    local compare_with_previous = with_path_do(function(path)
      u.diff_files(
        'tfvc:///files/C' .. tonumber(cs) - 1 .. '/' .. path,
        'tfvc:///files/C' .. cs .. '/' .. path)
    end)
    local compare_with_latest = with_path_do(function(path)
      u.diff_files(
        'tfvc:///files/C' .. cs .. '/' .. path,
        'tfvc:///files/T/' .. path)
    end)
    local compare_with_local = with_path_do(function(path)
      u.diff_files(
        'tfvc:///files/C' .. cs .. '/' .. path,
        path)
    end)
    local view_file_version = with_path_do(function(path)
      vim.cmd('e tfvc:///files/C' .. cs .. '/' .. path)
    end)

    local inline_diff = with_path_do(function(path)
      local mark = u.get_mark_under_cursor()
      if mark then
        return
      end
      local inline_cmd = {
        'diff', '/version:C' .. tonumber(cs) - 1 .. '~' .. cs, path, '/format:Unified'
      }

    local row = vim.api.nvim_win_get_cursor(0)[1]
      u.tf_cmd(inline_cmd, { print_stdout = false, memoize = true },
      function (obj)
        u.inline_diff.insert(obj.stdout or obj.stderr, buf, row)
      end)
    end)

    local map = mapbuf(buf)
    map('n', 'g?', '<cmd>map <buffer><CR>' , 'Show Help')
    map('n', '>', inline_diff, 'Show inline diff')
    map('n', '<', function() u.inline_diff.del(buf) end, 'Hide inline diff')
    map('n', 'gf', view_file_version, 'Show File under cursor')
    map('n', 'dl', compare_with_local, 'Compare File under cursor with local version')
    map('n', 'dt', compare_with_latest, 'Compare File under cursor with latest server version')
    map('n', 'dd', compare_with_previous, 'Compare File under cursor with previous version')
    map('n', '<CR>', compare_with_previous, 'Compare File under cursor with previous version')
  end))
end

function M.files_bufreadcmd(args)
  local buf = args.buf
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
    vim.api.nvim_buf_call(buf, function()

      vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
      vim.cmd('noautocmd keepalt keepjumps silent read ++edit ' .. vim.fn.fnameescape(file_path))
      vim.api.nvim_buf_set_lines(buf, 0, 1, true, {}); -- replace first line with no lines (i.e. delete first line)

      vim.b[buf].versionspec = versionspec
      vim.b[buf].local_path = path
      vim.b[buf].is_server_file = true

      -- if we're opening this file as part of a file-diff
      -- and we're not collapsing unchaged regions (diff_open_folds)
      -- then per default we'd just be at line 1, instead of viewing the changes
      -- so we're moving to the first change with ]c
      --
      -- not sure if this is the right place for this logic,
      -- but we can only move the cursor after the file is fully loaded
      -- maybe we'll need a custom event
      local isdiff = vim.api.nvim_get_option_value( 'diff', { win = 0 })
      if isdiff and require('tfvc.options').diff_open_folds then
        vim.schedule(function ()
          vim.cmd ':norm ]c'
        end)
      end

      -- must detect filetype before setting filetype
      vim.cmd [[ filetype detect ]]
      M.set_tfvc_buf_opts(buf, true)

      -- keymaps
      local cs = nil
      local is_changeset_vs = versionspec:sub(1,1) == 'C'
      if is_changeset_vs then
        cs = tonumber(versionspec:sub(2))
      end

      local function server_file_info()
        local info_content = {
          '# TFVC Serverfile',
          '# Path: ' .. path,
          '# Versionspec: ' .. versionspec,
          "# '<leader>te' to goto to the local file of this server file",
          "# '<leader>th' to view the history of this file",
        }
        if cs then
          local extra = "# '-' to view the changeset associated with this fileversion"
          table.insert(info_content, extra)
        end
        vim.print(table.concat(info_content, '\n'))
      end
      local keymapOpt = { buffer = buf }
      vim.keymap.set('n', '<leader>tc','<cmd>echo "Cannot checkout server-file"<CR>' , keymapOpt)
      vim.keymap.set('n', '<leader>ti', server_file_info, keymapOpt)
      vim.keymap.set('n', '<leader>te', '<cmd>e '.. path .. '<CR>', keymapOpt)
      if cs then
        local changeset_uri = 'tfvc:///changeset/' .. cs
        vim.keymap.set('n', '-', '<cmd>e '.. changeset_uri .. '<CR>', keymapOpt)
      end
    end)
  end)
end

return M
