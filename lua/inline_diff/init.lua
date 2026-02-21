local M = {}

---@param target_buf number
---@param path_compare_base string
function M.setup_inline_diff(target_buf, path_compare_base)
  local diff = require('inline_diff.diff');
  if M.has_active_inline_diff(target_buf) then
    M.stop_inline(target_buf)
  end
  diff.setup_inline_diff(target_buf, path_compare_base)
end

function M.stop_inline(buf)
  require('inline_diff.diff').stop_inline_diff(buf)
end

function M.has_active_inline_diff(buf)
  return vim.b[buf].unified_diff_augroup_id ~= nil
end

return M
