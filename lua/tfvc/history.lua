local M = {}
local u = require('tfvc.utils')
local state = require('tfvc.state')

--- unused
--- parses the output of the tf history command
--- unnecessary since we can just open the web interface and don't have to
--- implement anything ourselves
--- if your server is slow its also much faster to open the web client than to issue commands via the cli tool
---@return table<historyChange>
local function parse_history(log)

  local history = {}
  local lines = u.line_iter(log)

::start::
  local changeset = nil
  local user = nil
  local date = nil
  local comment = nil
  local changeType = nil

  while (lines.next()) do
    local line = lines.current()
    if string.match(line, 'Changeset:') then
      changeset = string.match(line, 'Changeset: (%d+)')
    end
    if string.match(line, 'User:') then
      user = string.match(line, 'User: (.+)')
    end
    if string.match(line, 'Date:') then
      date = string.match(line, 'Date: (.+)')
    end
    if string.match(line, 'Comment:') then
      if lines.next() then
        comment = lines.current()
      end
    end

    if string.match(line, '+\\-') then
      table.insert(history, {
        changeset = changeset,
        user = user,
        date = date,
        comment = comment,
        changeType = changeType,
      })
      goto start
    end
  end

  table.insert(history, {
    changeset = changeset,
    user = user,
    date = date,
    comment = comment,
    changeType = changeType,
  })

  return history
end

---@class historyChange
---@field changeset string
---@field user string
---@field date string
---@field comment string
---@field changeType string
---@field localPath string
---@field serverPath string

---@param localPath string
---@param workfold workfold
---@return string
function M.map_local_path_to_server_path(localPath, workfold)
  local serverPath = localPath:gsub(workfold.localPath, workfold.serverPath)
  return serverPath
end

function M.cmd_open_web_history()
  local workfold = state.get_workfold_or_get_cached()
  if not workfold then
    vim.notify('Workfold not initialized. Try Again', vim.log.levels.ERROR)
    return
  end

  if not vim.g.tf.version_control_web_url then
    vim.notify('Version control web url not initialized', vim.log.levels.ERROR)
    return
  end
  local file = u.get_current_file('open_web_history')
  if not file then
    return
  end

  local serverPath = M.map_local_path_to_server_path(file, workfold)
  local escapedServerPath = u.url_encode(serverPath) or ''
  escapedServerPath = escapedServerPath:gsub('%%2E', '.')

  local full_url = vim.g.tf.version_control_web_url .. '/?path=' .. escapedServerPath .. '&_a=history'
  if state.debug then
    vim.notify(full_url)
  end
  vim.ui.open(full_url)
  --u.open_url(full_url)
end

return M
