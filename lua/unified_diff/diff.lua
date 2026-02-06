local M = {}

--------------------------------------------------------------------------------
local hunk_store = {}

---@param bufnr integer The buffer number to store hunks for.
---@param lines table A list of line numbers where hunks start.
function hunk_store.set(bufnr, lines)
  vim.b[bufnr].unified_hunks = lines
end

---@param bufnr integer The buffer number to retrieve hunks from.
---@return table A list of line numbers where hunks start, or an empty table.
function hunk_store.get(bufnr)
  return vim.b[bufnr].unified_hunks or {}
end

---@param bufnr integer The buffer number to clear hunks from.
function hunk_store.clear(bufnr)
  vim.b[bufnr].unified_hunks = nil
end

---@class unified_diff.hunk
---@field old_start number
---@field old_count number
---@field new_start number
---@field new_count number
---@field lines string[]
--------------------------------------------------------------------------------

M.ns_id = vim.api.nvim_create_namespace("unified_diff")

local config = {
  values = {
    signs = {
      add = "│",
      delete = "│",
      change = "│",
    },
    highlights = {
      add = "DiffAdd",
      delete = "DiffDelete",
      change = "DiffChange",
    },
    line_symbols = {
      add = "+",
      delete = "-",
      change = "~",
    },
    auto_refresh = true, -- Whether to auto-refresh diff when buffer changes
  }
}

local function write_buf_contents_to_tmp(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local linebreak_mapping = { dos = '\r\n', unix = '\n', mac = '\r', }
  local ff = vim.bo[buf].fileformat
  local linebreak = linebreak_mapping[ff]
  assert(linebreak, "fileformat must be 'dos', 'unix', or 'mac'")
  local content = table.concat(lines, linebreak)
  if vim.bo[buf].endofline then
    content = content .. "\n"
  end
  local tmp = vim.fn.tempname()
  local f = io.open(tmp, "wb")
  assert(f, 'must be able to write to tmp file from vim.fn.tempname()')
  f:write(content)
  f:close()
  return tmp
end

function M.__diff_buf_against_file(target_buf, target_path, path_compare_base)

  local target = target_path
  if vim.api.nvim_get_option_info2('modified', { buf = target_buf}) then
    -- if modified we need to write the unsaved buffer content to a temporary file that we can hand over to diff
    target = write_buf_contents_to_tmp(target_buf)
  end

  local diff_output = vim.fn.system({ "diff", "-u", path_compare_base, target })
  local hunks = M.parse_diff(diff_output)
  M.display_inline_diff(target_buf, hunks)
end

-- Parse diff and return a structured representation
---@return unified_diff.hunk[]
function M.parse_diff(diff_text)
  local lines = vim.split(diff_text, "\n")
  ---@type unified_diff.hunk[]
  local hunks = {}

  ---@type unified_diff.hunk|nil
  local current_hunk = nil

  for _, line in ipairs(lines) do
    if line:match("^@@") then
      -- Hunk header line like "@@ -1,7 +1,6 @@"
      if current_hunk then
        table.insert(hunks, current_hunk)
      end

      -- Parse line numbers
      local old_start, old_count, new_start, new_count = line:match("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

      old_count = old_count ~= "" and tonumber(old_count) or 1
      new_count = new_count ~= "" and tonumber(new_count) or 1

      current_hunk = {
        old_start = tonumber(old_start),
        old_count = old_count,
        new_start = tonumber(new_start),
        new_count = new_count,
        lines = {},
      }
    elseif current_hunk and (line:match("^%+") or line:match("^%-") or line:match("^ ")) then
      table.insert(current_hunk.lines, line)
    end
  end

  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return hunks
end

---@param buffer number
---@param hunks unified_diff.hunk[]
function M.display_inline_diff(buffer, hunks)

  vim.api.nvim_buf_clear_namespace(buffer, M.ns_id, 0, -1)

  -- Clear existing signs
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  local new_hunk_lines = {}

  -- Track if we placed any marks
  local mark_count = 0
  local sign_count = 0

  -- Get current buffer line count for safety checks
  local buf_line_count = vim.api.nvim_buf_line_count(buffer)

  -- Track which lines have been marked already to avoid duplicates
  local marked_lines = {}

  -- For detecting multiple consecutive new lines
  local consecutive_added_lines = {}

  local in_changed_block = false

  for _, hunk in ipairs(hunks) do
    local line_idx = math.max(hunk.new_start - 1, 0)
    local old_idx = 0
    local new_idx = 0

    -- First pass: identify ranges of consecutive added lines
    local current_start = nil
    local added_count = 0

    -- Analyze hunk lines to find consecutive added lines
    for _, line in ipairs(hunk.lines) do
      local first_char = line:sub(1, 1)

      if first_char == config.values.line_symbols.add then
        -- Start a new range or extend current range
        if current_start == nil then
          current_start = hunk.new_start - 1 + new_idx
          added_count = 1
        else
          added_count = added_count + 1
        end
      else
        -- End of added range, record it if we found multiple additions
        if current_start ~= nil and added_count > 0 then
          consecutive_added_lines[current_start] = added_count
          current_start = nil
          added_count = 0
        end
      end

      -- Update counters for proper position tracking
      if first_char == " " then
        new_idx = new_idx + 1
      elseif first_char == config.values.line_symbols.add then
        new_idx = new_idx + 1
      end
    end

    -- Record final range if needed
    if current_start ~= nil and added_count > 0 then
      consecutive_added_lines[current_start] = added_count
    end

    -- Reset for the main pass
    line_idx = hunk.new_start - 1
    old_idx = 0
    new_idx = 0
    in_changed_block = false

    local deleted_lines = {}
    local deleted_attach_line = nil

    local function flush_deleted_lines()
      if #deleted_lines == 0 then
        return
      end
      if buf_line_count == 0 then
        deleted_lines = {}
        deleted_attach_line = nil
        return
      end

      assert(deleted_attach_line, 'deleted_attach_line is not nil at this point')

      local attach_line = math.min(deleted_attach_line, buf_line_count - 1)
      local virt_lines = {}
      for _, text in ipairs(deleted_lines) do
        table.insert(virt_lines, { { text, "UnifiedDiffDelete" } })
      end

      local mark_id = vim.api.nvim_buf_set_extmark(buffer, M.ns_id, attach_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = deleted_attach_line > 0,
      })
      if mark_id > 0 then
        mark_count = mark_count + #deleted_lines
      end

      deleted_lines = {}
      deleted_attach_line = nil
    end

    for _, line in ipairs(hunk.lines) do
      local first_char = line:sub(1, 1)

      if first_char == config.values.line_symbols.add or first_char == config.values.line_symbols.delete then
        if not in_changed_block then
          table.insert(new_hunk_lines, line_idx + 1)
          in_changed_block = true
        end
      else
        in_changed_block = false
      end

      if first_char == " " then
        -- Context line
        flush_deleted_lines()
        line_idx = line_idx + 1
        old_idx = old_idx + 1
        new_idx = new_idx + 1
      elseif first_char == "+" then
        -- Added or modified line
        flush_deleted_lines()
        local hl_group = "UnifiedDiffAdd"

        -- Process only if line is within range and not already marked
        if line_idx < buf_line_count and not marked_lines[line_idx] then
          -- Check if this is part of consecutive added lines
          local consecutive_count = consecutive_added_lines[line_idx - new_idx + old_idx] or 0

          -- Use a single extmark with both sign and line highlighting
          local extmark_opts = {
            sign_text = config.values.line_symbols.add .. " ", -- Add sign in gutter
            sign_hl_group = config.values.highlights.add,
            line_hl_group = hl_group,
          }
          local mark_id = vim.api.nvim_buf_set_extmark(buffer, M.ns_id, line_idx, 0, extmark_opts)
          if mark_id > 0 then
            mark_count = mark_count + 1
            sign_count = sign_count + 1
            marked_lines[line_idx] = true

            -- If part of consecutive additions, highlight subsequent lines
            if consecutive_count > 1 then
              for i = 1, consecutive_count - 1 do
                local next_line_idx = line_idx + i

                -- Process only if next line is within range and not already marked
                if next_line_idx < buf_line_count and not marked_lines[next_line_idx] then
                  -- Use a single extmark with both sign and line highlighting for consecutive lines
                  local consec_extmark_opts = {
                    sign_text = config.values.line_symbols.add .. " ", -- Add sign in gutter
                    sign_hl_group = config.values.highlights.add,
                    line_hl_group = hl_group,
                  }
                  local consec_mark_id =
                    vim.api.nvim_buf_set_extmark(buffer, M.ns_id, next_line_idx, 0, consec_extmark_opts)
                  if consec_mark_id > 0 then
                    mark_count = mark_count + 1
                    sign_count = sign_count + 1
                    marked_lines[next_line_idx] = true
                  end
                end
              end
            end
          end
        end

        line_idx = line_idx + 1
        new_idx = new_idx + 1
      elseif first_char == "-" then
        local line_text = line:sub(2)
        if deleted_attach_line == nil then
          deleted_attach_line = math.max(line_idx, 0)
        end
        if line_text == '' then
          line_text = string.rep(' ', 500)
        end
        table.insert(deleted_lines, line_text)

        old_idx = old_idx + 1
      end
    end

    flush_deleted_lines()
  end

  if #new_hunk_lines > 0 then
    table.sort(new_hunk_lines)
    local unique_lines = { new_hunk_lines[1] }
    for i = 2, #new_hunk_lines do
      if new_hunk_lines[i] > unique_lines[#unique_lines] then
        table.insert(unique_lines, new_hunk_lines[i])
      end
    end
    hunk_store.set(buffer, unique_lines)
  else
    hunk_store.clear(buffer)
  end
  return mark_count > 0
end

-- Function to check if diff is currently displayed in a buffer
function M.is_diff_displayed(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(buffer, M.ns_id, 0, -1, {})
  return #marks > 0
end

local refresh = {
  debounce_delay = 300,
  augroup_name = "UnifiedDiffAutoRefresh",
}

---@param target_buf number
---@param path_compare_base string
function M.setup_unified_diff(target_buf, path_compare_base)

  local target_path = vim.api.nvim_buf_call(target_buf, function()
    return vim.fn.expand('%')
  end)

  assert(target_path, 'Can only diff on file-buffers')

  local active_refresher = vim.b[target_buf].unified_diff_augroup_id
  assert(active_refresher == nil, 'cannot setup unified-diffs twice')

  local async = require("unified_diff.async")
  local augroup = vim.api.nvim_create_augroup(refresh.augroup_name, { clear = true })

  local debounced_show_diff = async.debounce(function()
    M.__diff_buf_against_file(target_buf, target_path, path_compare_base)
  end, refresh.debounce_delay)

  ---@diagnostic disable-next-line: param-type-mismatch
  vim.api.nvim_create_autocmd({
    'TextChanged',
    'InsertLeave',
    'FileChangedShell',
  }, {
    group = augroup,
    buffer = target_buf,
    callback = function()
        debounced_show_diff()
    end,
  })

  -- and initial diffing
  M.__diff_buf_against_file(target_buf, target_path, path_compare_base)

  vim.b[target_buf].unified_diff_augroup_id = augroup
end

function M.stop_unified(buffer)
  local augroup = vim.b[buffer].unified_diff_augroup_id
  assert(augroup, 'cannot stop unified_diff on buffer without active autocommands for ud')

  vim.api.nvim_clear_autocmds({ buffer = buffer, group = augroup })
  vim.api.nvim_buf_clear_namespace(buffer, M.ns_id, 0, -1)
  vim.fn.sign_unplace("unified_diff", { buffer = buffer })

  vim.b[buffer].unified_diff_augroup_id = nil
end

return M
