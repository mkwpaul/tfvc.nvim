local M = {}
local options = require('tfvc.options')

function M.check()
  local health = vim.health or require "health"

  local tf = options.executable_path
  if vim.fn.executable(tf) == 1 then
    health.ok("tf executable '" .. tf .."' found")
  else
    health.error("tf executable '" .. tf .."' not found. Manually set the full path to the tf executable or include it in your PATH")
  end

  if options.version_control_web_url then
    health.ok("version_control_web_url set")
  else
    health.warn("version_control_web_url not set. Open Web History command will not work.")
  end

  health.info('Checking options...')
  for key, _ in pairs(options.option_definitions) do
    local success, msg, isuserval = pcall(options.get_option, key)
    if not success then
      assert(type(msg) == 'string')
      health.error(msg)
    else
      local msg = key .. ' = ' ..vim.inspect(msg)
      if not isuserval then
        msg = '(default): '..msg
      end
      health.info(msg)
    end
  end

end

return M
