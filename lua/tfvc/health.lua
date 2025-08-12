local M = {}
local state = require('tfvc.state')

function M.check()
  local health = vim.health or require "health"

  health.start("tfvc report")

  local tf = state.tf()
  if vim.fn.executable(tf) == 1 then
    health.ok("tfvc: tf executable '" .. tf .."' found")
  else
    health.error("tfvc: tf executable '" .. tf .."' not found. Manually set the full path to the tf executable via tfvc.setup() or include it in your PATH")
  end

  local telescope = pcall(require, 'telescope')
  if telescope then
    health.ok('tfvc: telescope found')
  else
    health.warn('tfvc: telescope not found. Status command will not work. Install telescope via your package manager')
  end

  local plenary_path = pcall(require, 'plenary.path')
  if plenary_path then
    health.ok('tfvc: plenary.path found')
  else
    health.warn('tfvc: plenary.path not found. Status command will only show full paths.')
  end

  local plenary_curl = pcall(require, 'plenary.path')
  if plenary_curl then
    health.ok('tfvc: plenary.curl found')
  else
    health.warn('tfvc: plenary.curl not found. Commands thta rely on making web requests will not work')
  end

  if vim.g.tf.version_control_web_url then
    health.ok("tfvc: version_control_web_url set")
  else
    health.warn("tfvc: version_control_web_url not set. Open Web History command will not work. Set the version_control_web_url in tfvc.setup() or execute the tf workfold command")
  end

  if vim.g.tf.workfold then
    health.ok("tfvc: workfold set")
  else
    health.warn("tfvc: workfold not set. Preset the workfold in tfvc.setup() or execute the tf workfold command. The workfold is required for the Open Web History command")
  end
end
return M
