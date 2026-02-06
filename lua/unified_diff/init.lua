local M = {}

---@param target_buf number
---@param path_compare_base string
function M.setup_unified_diff(target_buf, path_compare_base)
  local diff = require('unified_diff.diff');
  if M.has_active_unified_diff(target_buf) then
    M.stop_unified(target_buf)
  end
  diff.setup_unified_diff(target_buf, path_compare_base)
end

function M.stop_unified(buf)
  require('unified_diff.diff').stop_unified(buf)
end

function M.has_active_unified_diff(buf)
  return vim.b[buf].unified_diff_augroup_id ~= nil
end

return M
