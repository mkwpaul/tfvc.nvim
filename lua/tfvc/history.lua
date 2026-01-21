local M = {}
local u = require('tfvc.utils')
local state = require('tfvc.state')

function M.changesets()
  local api = require ('tfvc.http-api')
  local response = api['/{organization}/{project}/_apis/tfvc/changesets']({})
end

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

  if not state.version_control_web_url then
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

  local full_url = state.version_control_web_url .. '/?path=' .. escapedServerPath .. '&_a=history'
  if state.debug then
    vim.notify(full_url)
  end
  vim.ui.open(full_url)
end

return M
