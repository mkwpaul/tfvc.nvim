
-- experimental
-- custom buffer type that's filled from CLI command output
-- to view history
-- custom buffer-local keymaps could be added to make browsing histories and changesets possible
--
-- currently only dumps the history of the CWD into the buffer without any interaction
--
-- for a proper implementation we would probably also need to query that information from the web-api directly
-- instead of relying on the CLI tool, which is quite limited (and slow)
local augroup_tfvc = vim.api.nvim_create_augroup('tfvc', { clear = true })
local default_history_limit = 300

-- this doesn't seem to work
-- :(
-- we probably would need to use ConPTY somehow,
-- but there isn't a convenient wrapper we can call
-- to run tf.exe in a context where we can specifly console text-encoding
-- and buffer-size column and line count
--
-- instead of specifying text encoding we can convert the text to utf-8 using iconv
-- but i'm not sure how to make custom buffer-size work
--
local test = [[cmd /C "mode con:cols=200 lines=58 & tf history . /recursive /stopafter:100 /noprompt]]

--vim.g.tf_output_encoding = nil

---@type tf_cmd_opts
local tfcmdOpts = {
  suppress_echo = true,
  return_stderr_on_failure = true,
}

vim.api.nvim_create_autocmd('BufReadCmd', {
  pattern = 'tfvc:///history/*',
  group = augroup_tfvc,
  callback = function(args)
    local buf = args.buf
    local bufOpt = { buf = buf }

    -- tell neovim that this buffer is now read-only and modifiable by us
    vim.api.nvim_set_option_value('modifiable', true, bufOpt)
    vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
    vim.api.nvim_set_option_value('swapfile', false, bufOpt)

    local path = args.file:gsub('tfvc:///history/', '') or '.'
    local limit = vim.g.tf_history_limit or default_history_limit
    local cmd = { 'history',  path, '/recursive', '/noprompt', '/stopafter:'..limit, '/format:brief' }
    local u = require('tfvc.utils')
    u.tf_cmd2(cmd, tfcmdOpts, vim.schedule_wrap(function(obj)
      -- Replace buffer content with command output
      vim.api.nvim_set_option_value('filetype', 'tf_history', bufOpt)
      vim.api.nvim_set_option_value('ff', 'dos', bufOpt)
      local output = obj.stdout or obj.stderr
      local lines = vim.split(output, '\r\n')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_option_value('modifiable', false, bufOpt)
      vim.api.nvim_set_option_value('modified', false, bufOpt)

      vim.keymap.set('n', '<CR>', function ()
        local line = vim.api.nvim_get_current_line()
        local cs_number = line:gmatch('%d+')()
        if cs_number then
          vim.cmd('e tfvc:///changeset/'..cs_number)
        end
      end, { buffer = buf })
    end))
  end,
})

-- basically the same as above, only we call a different tf command + no custom keymap
vim.api.nvim_create_autocmd('BufReadCmd', {
  pattern = 'tfvc:///changeset/*',
  group = augroup_tfvc,
  callback = function(args)
    local buf = args.buf
    local bufOpt = { buf = buf }

    -- tell neovim that this buffer is now read-only and modifiable by us
    vim.api.nvim_set_option_value('modifiable', true, bufOpt)
    vim.api.nvim_set_option_value('swapfile', false, bufOpt)
    vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)

    local cs = args.file:gsub('tfvc:///changeset/', '')
    local cmd = { 'changeset', cs, '/noprompt',  }

    local u = require('tfvc.utils')
    u.tf_cmd2(cmd, tfcmdOpts, vim.schedule_wrap(function(obj)
      -- Replace buffer content with command output
      vim.api.nvim_set_option_value('filetype', 'tf_changeset', bufOpt)
      vim.api.nvim_set_option_value('ff', 'dos', bufOpt)
      local output = obj.stdout or obj.stderr
      local lines = vim.split(output, '\r\n')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_option_value('modifiable', false, bufOpt)
      vim.api.nvim_set_option_value('modified', false, bufOpt)
    end))
  end,
})

vim.api.nvim_create_autocmd('BufReadCmd', {
  pattern = 'tfvc:///files/*',
  group = augroup_tfvc,
  callback = function(args)
    local buf = args.buf
    local bufOpt = { buf = buf }

    -- tell neovim that this buffer is now read-only and modifiable by us
    vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
    vim.api.nvim_set_option_value('modifiable', true, bufOpt)
    vim.api.nvim_set_option_value('swapfile', false, bufOpt)

    local path = args.file:gsub('tfvc:///files/', '')
    local versionspec = 'T'
    local idx = path:find('/', 0, true)
    if (idx) then
      versionspec = path:sub(1, idx - 1)
      path = path:sub(idx + 1, nil)
    end

    local u = require 'tfvc.utils'
    u.tf_get_version_from_versionspec(path, versionspec, false, function (file_path)
      local lines = vim.fn.readfile(file_path)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_option_value('modifiable', false, bufOpt)
      vim.api.nvim_set_option_value('modified', false, bufOpt)
      -- vim.api.nvim_buf_call(buf, function()
      --   vim.cmd('noautocmd keepalt keepjumps silent read ++edit ' .. vim.fn.fnameescape(file_path))
      -- end)
    end)
  end,
})


