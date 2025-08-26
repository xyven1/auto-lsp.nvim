local vim = vim

local augroup = vim.api.nvim_create_augroup
local doautocmd = vim.api.nvim_exec_autocmds

local function doautoall(event, opts)
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    opts.buffer = bufnr
    doautocmd(event, opts)
  end
end

local function dofiletype(ft, opts)
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    if vim.bo[bufnr].filetype == ft then
      opts.buffer = bufnr
      doautocmd("FileType", opts)
    end
  end
end

local M = {}

function M:new(opts)
  -- add user specified server filetypes to the filetype:servers mapping
  for name, config in pairs(opts.server_config) do
    if not (type(config) == "table") then
      goto continue
    end

    for _, ft in ipairs(config.filetypes or {}) do
      local ft_servers = opts.filetype_servers[ft] or {}
      if not vim.list_contains(ft_servers, name) then
        ft_servers[#ft_servers + 1] = name
      end
      opts.filetype_servers[ft] = ft_servers
    end

    ::continue::
  end

  opts.checked_filetypes = {}
  opts.checked_servers = {}

  return setmetatable(opts, { __index = self })
end

function M:check_server(name, recheck)
  local did_setup = self.checked_servers[name]
  if did_setup == true or (did_setup == false and not recheck) then
    return
  end

  local config = self.server_config[name]
  local exec = self.server_executable[name]

  if type(config) == "function" then
    config = config()
  elseif type(config) == "table" then
    config = config
  elseif type(config) == "boolean" then
    config = config and {}
  else
    config = exec and vim.fn.executable(exec) == 1 and {}
  end

  if config then
    if type(self.global_config) == "function" then
      self.global_config = self.global_config()
    end

    config = vim.tbl_deep_extend("force", self.global_config, config)
    vim.lsp.config[name] = config
    vim.lsp.enable(name)
  end

  self.checked_servers[name] = config and true or false
end

function M:check_generics(recheck)
  for _, name in ipairs(self.generic_servers) do
    vim.schedule(function()
      self:check_server(name, recheck)
    end)
  end

  vim.schedule(function()
    doautoall("BufReadPost", {
      group = augroup("lspconfig", { clear = false }),
      modeline = false,
    })
  end)
end

function M:check_filetype(ft, recheck)
  if self.checked_filetypes[ft] == true and not recheck then
    return
  end
  self.checked_filetypes[ft] = true

  local ft_servers = self.filetype_servers[ft]
  if not ft_servers then
    return
  end

  for _, name in ipairs(ft_servers) do
    vim.schedule(function()
      self:check_server(name)
    end)
  end

  vim.schedule(function()
    dofiletype(ft, {
      group = augroup("lspconfig", { clear = false }),
      modeline = false,
    })
  end)
end

function M:refresh()
  for name, did_setup in pairs(self.checked_servers) do
    if not did_setup then
      vim.schedule(function()
        self:check_server(name, true)
      end)
    end
  end

  vim.schedule(function()
    doautoall({ "FileType", "BufReadPost" }, {
      group = augroup("lspconfig", { clear = false }),
      modeline = false,
    })
  end)
end

return M
