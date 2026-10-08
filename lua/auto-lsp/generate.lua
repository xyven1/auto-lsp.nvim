local vim = vim
local uv = vim.uv

-- filter out language / package manager commands e.g. python -m <module>
local ignored_executables = {
  R = true,
  dotnet = true,
  java = true,
  julia = true,
  nc = true,
  node = true,
  npx = true,
  perl = true,
  python = true,
  python3 = true,
  racket = true,
}

-- find the executable a function `cmd` would spawn, by calling it with the
-- rpc transports stubbed out so that nothing is actually started
---@param cmd fun(dispatchers: table, config: table)
---@return string|true exec the executable, or true if it can't be determined
local function probe_cmd(cmd)
  local rpc = vim.lsp.rpc
  local start, connect = rpc.start, rpc.connect
  local new_tcp, new_pipe = uv.new_tcp, uv.new_pipe
  local exec

  local function abort()
    error("auto-lsp: probe")
  end
  rpc.start = function(spawn_cmd)
    exec = type(spawn_cmd) == "table" and spawn_cmd[1] or spawn_cmd
    abort()
  end
  -- `cmd` may itself be the result of `vim.lsp.rpc.connect()`, so the sockets
  -- have to be blocked as well
  rpc.connect, uv.new_tcp, uv.new_pipe = abort, abort, abort
  pcall(cmd, {}, {})
  rpc.start, rpc.connect = start, connect
  uv.new_tcp, uv.new_pipe = new_tcp, new_pipe

  return type(exec) == "string" and exec or true
end

local function generate(config_dirs)
  local generic_servers = {}
  local filetype_servers = {}
  local server_executable = {}

  for _, config_dir in ipairs(config_dirs) do
    local config_files = vim.fn.readdir(config_dir)
    for _, file in ipairs(config_files) do
      local name = vim.fn.fnamemodify(file, ":r")
      local path = vim.fs.joinpath(config_dir, file)
      local file_content = vim.fn.readfile(path)
      local is_deprecated = false
      for _, line in ipairs(file_content) do
        if line:match("vim%.deprecate") then
          is_deprecated = true
          break
        end
      end
      if not is_deprecated then
        local config = dofile(path)
        if config.filetypes then
          for _, ft in ipairs(config.filetypes) do
            filetype_servers[ft] = filetype_servers[ft] or {}
            table.insert(filetype_servers[ft], name)
          end
        else
          table.insert(generic_servers, name)
        end

        if not config.cmd then
          vim.notify(
            string.format(
              "auto-lsp: No 'cmd' field found for server '%s' in file '%s'",
              name,
              path
            ),
            vim.log.levels.WARN
          )
        elseif type(config.cmd) == "table" then
          local exec = config.cmd[1]
          if not ignored_executables[exec] then
            server_executable[name] = exec
          end
        elseif type(config.cmd) == "function" then
          local exec = probe_cmd(config.cmd)
          if not ignored_executables[exec] then
            server_executable[name] = exec
          end
        end
      end
    end
  end

  return {
    generic_servers = generic_servers,
    filetype_servers = filetype_servers,
    server_executable = server_executable,
    sources = vim.tbl_map(function(config_dir)
      return {
        path = config_dir,
        mtime = uv.fs_stat(config_dir).mtime.sec,
      }
    end, config_dirs),
  }
end

return generate
