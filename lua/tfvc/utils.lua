local M = {}

---@type table<tfvc.file_version>
M.file_versions = {}
---@type table<tfvc.pending_change>
M.pending_changes = {}
---@type number|nil
M.pending_changes_last_updated = nil
---@type tfvc.workfold[] cached from output or user-provided
M.workfolds = {}

---@param local_path string
function M.get_local_path_relative(local_path)
  local cwd = vim.fs.normalize(vim.fn.getcwd(0))
  if vim.startswith(local_path, cwd) then
    local_path = local_path:sub(#cwd + 1)
  end
  if (local_path:sub(1,1) == '\\') or (local_path:sub(1,1) == '/') then
    local_path = local_path:sub(2)
  end
  return local_path
end

---@param full_path string 
---@return boolean
function M.is_within_workspace(full_path)
  -- paths on windows are case insensitive by default
  -- i think you can optionally make them case sensitive, but lets not worry about that :^)
  -- I also doubt anyone will use this on a linux system where paths are case sensitive
  full_path = vim.fs.normalize(full_path:lower())
  local cwd = vim.fs.normalize(vim.fn.getcwd(0):lower())
  return vim.startswith(full_path, cwd)
end

function M.get_cache_path(subfolder, args)
  local cache_root = vim.fn.stdpath('cache')
  local args_joined = table.concat(args, '_');
  local url_encoded = M.url_encode(args_joined)
  local result_path = vim.fs.joinpath(cache_root, 'tfvc', subfolder, url_encoded)
  return result_path
end

local function read_file(file)
  local f = assert(io.open(file, "rb"))
  local content = f:read("*all")
  f:close()
  return content
end

local function write_file(file, contents)
  assert(file, 'argument file is nil')
  assert(contents, 'argument contents is nil')

  local dir = vim.fs.dirname(file)
  if not vim.uv.fs_stat(dir) then
    vim.fn.mkdir(dir)
  end

  --
  -- w is "write mode", but write mode is TEXT write mode,
  -- which, on windows, replaces all \n characters with \r\n
  -- our file-contents already have \r\n line breaks
  -- so we end up with \r\r\n line breaks...
  --
  -- hence why we're using 'wb' (binary write mode)
  -- because it disables that crap.
  local f = assert(io.open(file, "wb"))
  f:write(contents)
  f:close()
end

---@class tfvc.tf_cmd_opts
---@field print_stdout boolean? should output be printed in messages?
---@field suppress_echo boolean? should command that was ran not be printed?
---@field return_stderr_on_failure boolean? should callback be called despite non-zero exit-code?
---@field memoize boolean? can output be cached, and subsequent calls be served by just retrieving the cached data?
---@field debug boolean? print full trace 

--- calls TF.exe with the specified arguments
---@param command string[] arguments to pass to TF.exe
---@param opts tfvc.tf_cmd_opts?
---@param callback fun(obj: vim.SystemCompleted)?
function M.tf_cmd(command, opts, callback)
  opts = opts or {}

  if opts.memoize then
    assert(callback, 'memoization is useless if you do not use the output')
    local path = M.get_cache_path('cmd', command)
    if path and vim.uv.fs_stat(path) then
      callback { stdout = read_file(path), signal = 0, code = 0, stderr = '', }
      return
    end
  end

  local v = require 'tfvc.options'
  table.insert(command, 1, v.executable_path)
  local command_string = table.concat(command, ' ')
  if not opts.suppress_echo then
    print(command_string)
  end

  local job = vim.system(command, nil, function(obj)
    vim.schedule(function ()
      if obj.code ~= 0 then
        local log = command_string .. '\n' .. 'Code:  ' .. obj.code .. '\n' .. (obj.stderr or '') .. (obj.stdout or '')
        vim.notify(log, vim.log.levels.ERROR)
      end

      if opts.print_stdout and obj.stdout then
        vim.notify(obj.stdout, vim.log.levels.INFO)
      end
    end)

    local o = require('tfvc.options')
    if o.debug then
      local log = 'Job finished: ' .. command_string .. '\n' .. 'Code:  ' .. obj.code .. '\n' .. obj.stderr .. obj.stdout
      vim.schedule(function()
        vim.notify(log, nil, nil)
      end)
    end

    if obj.code ~= 0 and not opts.return_stderr_on_failure then
      return
    end

    -- we only need re-encode output streams
    -- if there's a callback that could possibly make use that output
    if callback then
      local source_enc = v.output_encoding
      if source_enc ~= 'UTF-8'  then
        local stdout = nil
        local stderr = nil
        if obj.stdout and obj.stdout ~= '' then
          stdout = vim.iconv(obj.stdout or '', source_enc, 'UTF-8')
        end
        if obj.stderr and obj.stderr ~= '' then
          stderr = vim.iconv(obj.stderr or '', source_enc, 'UTF-8')
        end
        obj = {
          stdout = stdout,
          stderr = stderr,
          code = obj.code,
          signal = obj.signal
        }
      end

      if opts.memoize then
        vim.schedule(function ()
          table.remove(command, 1)
          local path = M.get_cache_path('cmd', command)
          write_file(path, obj.stdout)
        end)
      end
      callback(obj)
    end
  end)
  return job
end

---@type table<string, fun(buf: number, uri: string):string> dictionary of uri-schemes and functions that resolve a local path for given a buffer and uri with that scheme
M.scheme_mappings = {
  ['file:'] = function(_, uri)
    if uri == 'file://' then
      return './'
    end
    return vim.uri_to_fname(uri)
  end,
  ['tfvc:///files/'] = function (buf, _)
    local p = vim.b[buf].local_path
    assert(type(p) == 'string', [[tfvc:///files buffer must have buffer-varialbe 'local_path' set]])
    return p
  end,
  ['oil:'] = function (buf, _)
    ---@diagnostic disable-next-line: return-type-mismatch
    return require('oil').get_current_dir(buf)
  end,
}

--- provide either buf or uri, preferably both, Pass buf = 0 if you want the path of the current buffer
---@param verb string? only used for logging when something goes wrong
---@param buf number? vim buffer id, falls back to current buffer if not set
---@param uri string? uri
---@return string? local_path
function M.get_local_path(verb, buf, uri)
  assert(uri or buf, 'must provide either uri or buf.')
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if uri and not buf then
    buf = buf or vim.uri_to_bufnr(uri)
  elseif not uri and buf then
    uri = vim.uri_from_bufnr(buf)
  end

  assert(uri and buf)

  for key, value in pairs(M.scheme_mappings) do
    if vim.startswith(uri, key) then
      local mapped = value(buf, uri);
      if mapped then mapped = vim.fs.normalize(mapped) end
      return mapped
    end
  end
  if verb then
    print('Command ' .. verb .. '. Invalid for non-file buffers: uri: ' .. uri)
  end
  return nil
end

function M.char_to_hex(c) return string.format("%%%02X", string.byte(c)) end

---@param url string?
---@return string?
function M.url_encode(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w ])", M.char_to_hex)
  url = url:gsub(" ", "+")
  return url
end

---@param path string tfvc server path
---@param versionspec tfvc.versionspec
function M.get_file_cache_path(path, versionspec)
  if versionspec == 'T' then
    return nil
  end
  if path:sub(1,1) ~= '$' then
    path = M.local_path_to_server_path(path)
  end

  local cache_root = vim.fn.stdpath('cache')
  local url_encoded = M.url_encode(versionspec) .. '___' .. M.url_encode(path)
  local result_path = vim.fs.joinpath(cache_root, 'tfvc', 'server_files', url_encoded)
  return result_path
end

---@param path string path to the file to get the version from
---@param versionspec tfvc.versionspec
---@param force_fresh boolean? If true, the buffer will be reloaded from the server
---@param callback fun(temp_file_path : string) continuation callback
function M.tf_get_version_from_versionspec(path, versionspec, force_fresh, callback)

  assert(type(versionspec) == 'string')
  assert(type(path) == 'string')

  local cache = M.file_versions

  if not force_fresh then
    for _, value in pairs(cache) do
      if (value.versionspec == versionspec and path == value.local_file) then
        callback(value.server_file)
        return
      end
    end
  end

  local temp = M.get_file_cache_path(path, versionspec)
  if temp and vim.uv.fs_stat(temp) then
    vim.print('got file from cache. avoided fetch from server')
    callback(temp)
    return
  end

  temp = temp or vim.fn.tempname()
  local cmd_opts = { suppress_echo = true, }

  local cmd = { 'vc', 'view', '/version:' .. versionspec, path, '/output:' .. temp }
  M.tf_cmd(cmd, cmd_opts , vim.schedule_wrap(function(obj)
    if obj.code == 0 then
      if obj.stdout then
        print(obj.stdout)
      end
      ---@type tfvc.file_version
      local cache_entry = {
        versionspec = versionspec,
        local_file = path,
        server_file = temp
      }

      -- remove existing cache entry if any
      for i, value in ipairs(cache) do
        if value.versionspec == versionspec and path == value.local_file then
          table.remove(cache, i)
          break
        end
      end
      table.insert(cache, cache_entry)
      callback(temp)
    end
  end))
end

--[[
$ tf workfold
==============================================================================================
Workspace : localMachine (tfs user)
Collection: [url to server]
 [TfsServerPath]: [MappedLocalPath]
--]]
---@param output string
---@return tfvc.workfold | nil
local function parse_tf_workfold(output)
  local n = 1
  local workfold = {}
  local lines = vim.split(output, '\n')
  local function next()
    n = n + 1
    return n <= #lines
  end
  local line_workspace = 'Workspace :'
  local line_collection = 'Collection: '
  while next() do
    local line = lines[n]
    if vim.startswith(line, line_workspace) then
      workfold.workspace = vim.trim(string.sub(line, #line_workspace + 1))
    end
    if vim.startswith(line, line_collection) then
      workfold.collection = vim.trim(string.sub(line, #line_collection + 1 ))
      -- line after collection is " [ServerPath]: [LocalPath]"
      if next() then
        local line_2 = lines[n]
        workfold.serverPath = vim.trim(string.sub(line_2, 1, string.find(line_2, ':') - 1))
        workfold.localPath = vim.trim(string.sub(line_2, string.find(line_2, ':') + 2))
        workfold.localPath = vim.fs.normalize(workfold.localPath)
      end
    end
  end

  if not workfold.serverPath
    or not workfold.localPath
    or not workfold.workspace then
    return nil
  end
  return workfold
end

---@return tfvc.workfold
function M.get_active_workfold()
  local options = require 'tfvc.options'
  local function try_get_from_cwd()
    local cwd = assert(vim.uv.cwd())
    cwd = vim.fs.normalize(cwd):lower()
    local function find_wf(workfold)
      local localPath = vim.fs.normalize(workfold.localPath)
      localPath = localPath:lower()
      return cwd:find(localPath, 0, true) ==1
    end
    return
      vim.iter(options.workfolds):find(find_wf) or
      vim.iter(M.workfolds):find(find_wf)
  end

  local wf = try_get_from_cwd()
  if wf then return wf end

  local job = M.tf_cmd({ 'workfold' }, { suppress_echo = true }, function(obj)
    local workfold = parse_tf_workfold(obj.stdout)
    if not workfold then
      error('Failed to get workfold: ' .. vim.inspect(obj))
    else
      table.insert(M.workfolds, workfold)
      wf = workfold
    end
  end)

  job:wait(3000)
  return wf
end

-- NOTE:
-- at this point it might be worth it to have a centralized 'path' type
-- from which all the different forms can be derived on-demand,
-- instead of passing different forms of paths (relative-local, absolute-local, server-path, normalized, file-uri)
-- everywhere and having to ensure that the different path-forms aren't mixed up
--

---@param server_path string
---@param relative boolean
---@return string path the mapped path
function M.server_path_to_local_path(server_path, relative)
  local workfold = M.get_active_workfold()
  local localpath, count = server_path:gsub(workfold.serverPath, workfold.localPath)
  if count ~= 1 then
    local data = { input_path = server_path, workfold = workfold }
    error('server_path_to_local_path, gsub of serverroot failed: ' .. vim.inspect(data), vim.log.levels.ERROR)
  end
  if relative then
    localpath = M.get_local_path_relative(localpath)
  end
  return localpath
end

---@param path string
---@return string path the mapped path
function M.local_path_to_server_path(path)
  assert(path)
  assert(path:sub(1,1) ~= '$', 'path must not be a tfvc server-path')

  local workfold = M.get_active_workfold()
  local rooted_path = vim.fs.abspath(path)
  local localpath, count = rooted_path:gsub(workfold.localPath, workfold.serverPath)
  if count ~= 1 then
    local data = { rooted_path = rooted_path, workfold = workfold }
    error('server_path_to_local_path, gsub of serverroot failed: ' .. vim.inspect(data), vim.log.levels.ERROR)
  end
  return localpath
end

function M.cmd_open_web_history()
  local v = require 'tfvc.options'
  local workfold = M.get_active_workfold()
  assert(workfold, 'Workfold must be initialized. Try Again.')
  assert(v.version_control_web_url, [[User-Option 'version_control_web_url' must be set for command 'open web history']])
  local file = M.get_local_path('open_web_history', 0)
  if not file then
    return
  end

  local serverPath, subcount = file:gsub(workfold.localPath, workfold.serverPath)
  assert(subcount == 1, 'mapping from local path to server path failed. This is expected when trying to map a file that\'s not part of the tfvc repository.')
  local escapedServerPath = M.url_encode(serverPath) or ''
  escapedServerPath = escapedServerPath:gsub('%%2E', '.')

  local full_url = v.version_control_web_url .. '/?path=' .. escapedServerPath .. '&_a=history'
  if v.debug then
    vim.notify(full_url)
  end
  vim.ui.open(full_url)
end

-- usually called before doing another diff-split
-- so we don't produce more splits than necessary
-- only affects current tab
function M.close_tfvc_diff_wins()
  local cur_win = vim.api.nvim_get_current_win()
  for _, win in pairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf_in_win = vim.api.nvim_win_get_buf(win)
    local is_server = vim.b[buf_in_win].is_server_file

    if win ~= cur_win and (is_server or vim.api.nvim_get_option_value('diff', { win = win })) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

function M.diff_files_inline(left, right)
  local _, inline_diff = pcall(require, 'inline_diff')
  if not inline_diff then
    vim.print("'inline_diff' could not be loaded", vim.log.levels.WARN)
    M.diff_files(left, right)
    return
  end

  local buf = vim.uri_to_bufnr(vim.uri_from_fname(right))
  if inline_diff.has_active_inline_diff(buf) then
    inline_diff.stop_inline(buf)
  else
    inline_diff.setup_inline_diff(buf, left)
  end
end

function M.diff_files(left, right)
  local u = require 'tfvc.utils'
  local vars = require 'tfvc.options'

  -- close wins that we previously opened
  -- otherwise new splits will acculumate when going throuhg multiple files
  -- which the user would have to close manually
  u.close_tfvc_diff_wins()
  vim.cmd.diffoff({ bang = true })
  vim.cmd ('keepjumps ' .. vars.diff_open_cmd ..  ' ' .. right)
  vim.cmd ('keepjumps diffsplit ' .. left)

  if vars.diff_no_split then vim.cmd ':norm q' end
  if vars.diff_open_folds then vim.cmd ':norm zr' end
  -- note that diff_open_folds has additional logic
  -- where the cursor is moved to the first change
  -- this is handeld in the tfvc:///files callback
end

---@param opts { diff_no_split:boolean?, diff_open_folds:boolean?, versionspec:string? }?
function M.tf_compare(opts)
  opts = opts or {}
  local path = M.get_local_path('tf_compare', 0)
  if not path then
    return
  end

  local versionspec = opts.versionspec or require('tfvc.options').default_versionspec
  M.close_tfvc_diff_wins()
  vim.cmd(':diffo!')
  vim.cmd.diffsplit('tfvc:///files/'..versionspec..'/'..path)

  local o = require 'tfvc.options'
  if opts.diff_no_split == nil then opts.diff_no_split = o.diff_no_split  end
  if opts.diff_open_folds == nil then opts.diff_open_folds = o.diff_open_folds end
  if opts.diff_no_split then vim.cmd ':norm q' end
  if opts.diff_open_folds then vim.cmd ':norm zr' end
end

function M.toggle_diff()
  local was_diff =  vim.api.nvim_get_option_value('diff', { win = 0 })
  if vim.b[0].is_server_file then
    local v = require('tfvc.options')
    if vim.b[0].versionspec == v.default_versionspec then
      vim.api.nvim_win_close(0, true)
      return
    end
  end
  if was_diff then
    M.close_tfvc_diff_wins()
    vim.cmd(':diffo!')
  else
    M.tf_compare()
  end
end

---@param files string[] list of file paths
---@param versionspec tfvc.versionspec?
function M.preload_versions_for_files(files, versionspec, force_fresh)
  versionspec = versionspec or require('tfvc.options').default_versionspec
  for _, file in pairs(files) do
    M.tf_get_version_from_versionspec(file, versionspec, force_fresh, function () end)
  end
end

function M.get_changeset_web_url(changeset)
  local vars = require('tfvc.options')
  local header = vars.version_control_web_url .. '/changeset/'.. changeset
  return header
end

-- status

---@param node xmlNode
---@param changes table<tfvc.pending_change>
local function iter_xml(node, changes)
  if node.tag == 'PendingChange' then
    ---@type tfvc.xmlPendingChange
    local props = node.attrs
    local pendingChange = {
      Change = props.chg or '',
      Local = vim.fs.normalize(props["local"]),
      item = props.item,
      type = props["type"],
      name = vim.fs.basename(props["local"])
    }
    table.insert(changes, pendingChange)
  end

  if node.children ~= nil then
    for _, v in pairs(node.children) do
      iter_xml(v, changes)
    end
  end
end

---@param status_xml string 
---@return table<tfvc.pending_change>
local function parse_status_xml(status_xml)
  local xmlparser = require('tfvc.xmlparser')
  local doc = xmlparser.parse(status_xml, false)
  local changes = {}
  iter_xml(doc, changes)
  return changes
end

---@param callback fun(changes:tfvc.pending_change[])
function M.get_pending_changes_async(callback)
  M.tf_cmd({ 'status', '/format:xml' }, nil, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function()
        vim.notify('Failed to get pending changes: ' .. vim.inspect(obj), vim.log.levels.ERROR)
      end)
      return
    end
    local changes = parse_status_xml(obj.stdout)
    M.pending_changes = changes
    M.pending_changes_last_updated = os.time()
    callback(changes)
  end)
end

---@param force_fresh boolean 
---@param callback fun(changes:tfvc.pending_change[])
function M.do_with_pending_changes(force_fresh, callback)
  if #M.pending_changes == 0 or force_fresh then
    M.get_pending_changes_async(callback)
  else
    callback(M.pending_changes)
  end
end

function M.change_type_to_icons(change)
  local words = vim.split(change or '', ' ', { plain = true, trimempty = true })
  local result = {}
  -- TODO: check if icons are availible / check an option
  for _, value in pairs(words) do
    if value == 'Add' then table.insert(result, '+') end
    if value == 'Edit' then table.insert(result, '✎') end
    if value == 'Delete' then table.insert(result, '🗑') end
    if value == 'Encoding' then table.insert(result, '🗎') end
    if value == 'Rollback' then table.insert(result, '←') end
  end
  return table.concat(result, ' ')
end

---@param pending_changes tfvc.pending_change[] 
---@param in_cwd boolean 
function M.load_pending_changes_into_qf(pending_changes, in_cwd)
  if in_cwd then
    pending_changes = vim.tbl_filter(function(change)
      return M.is_within_workspace(change.Local)
    end, pending_changes)
  end
  local qf_entries = vim.tbl_map(function (change)
    return {
      filename = change.Local,
      valid = true,
      text = M.change_type_to_icons(change.Change) .. ' ' .. change.Change
    }
  end, pending_changes)

  vim.fn.setqflist(qf_entries)
  vim.cmd.copen()
end

return M
