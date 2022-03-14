local buffer_repository = require("cmdbuf.lib.repository").Repository.new("buffer")

local M = {}

local Buffer = {}
Buffer.__index = Buffer
M.Buffer = Buffer

function Buffer.get_or_create(handler, line)
  local name = ("cmdbuf://%s-buffer"):format(handler.name)
  local bufnr = vim.fn.bufnr(("^%s$"):format(name))
  if bufnr == -1 then
    return Buffer.create(handler, name, line), true
  end

  -- NOTE: the buffer is empty if it was closed by `:quit!`
  vim.fn.bufload(bufnr)

  if line then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { line })
  end
  return Buffer.get(bufnr), false
end

function Buffer.create(handler, name, line)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local tbl = { _bufnr = bufnr, _handler = handler }
  local self = setmetatable(tbl, Buffer)
  buffer_repository:set(bufnr, self)

  self:load(line)

  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", [[<Cmd>lua require("cmdbuf").execute({quit = true})<CR>]], {})
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<CR>", [[<ESC><Cmd>lua require("cmdbuf").execute({quit = true})<CR>]], {})

  vim.cmd(("autocmd BufReadCmd <buffer=%s> lua require('cmdbuf.command').reload(%s)"):format(bufnr, bufnr))
  vim.cmd(
    ("autocmd WinClosed <buffer=%s> lua require('cmdbuf.command').on_win_closed(tonumber(vim.fn.expand('<afile>')))"):format(
      bufnr
    )
  )
  vim.cmd(("autocmd BufWipeout <buffer=%s> lua require('cmdbuf.command').cleanup(%s)"):format(bufnr, bufnr))

  return self
end

function Buffer.get(bufnr)
  vim.validate({ bufnr = { bufnr, "number" } })
  local buffer = buffer_repository:get(bufnr)
  if not buffer then
    error(("state is not found in buffer: %s"):format(bufnr))
  end
  return buffer
end

function Buffer.current()
  local bufnr = vim.api.nvim_get_current_buf()
  return Buffer.get(bufnr)
end

function Buffer.load(self, line)
  vim.validate({ line = { line, "string", true } })

  local lines = self._handler:histories()
  table.insert(lines, line or "")
  vim.api.nvim_buf_set_lines(self._bufnr, 0, -1, false, lines)

  vim.bo[self._bufnr].filetype = self._handler.filetype
end

function Buffer.execute(self, row, close_window)
  vim.validate({ row = { row, "number" }, close_window = { close_window, "function" } })

  local line = vim.api.nvim_buf_get_lines(self._bufnr, row - 1, row, false)[1]
  self._handler:add_history(line)

  close_window()

  if line == "" then
    return nil
  end
  return self._handler:execute(line)
end

function Buffer.delete_range(self, s, e)
  vim.validate({ s = { s, "number" }, e = { e, "number" } })
  local lines = vim.api.nvim_buf_get_lines(self._bufnr, s, e, false)
  self._handler:delete_histories(lines)
  vim.api.nvim_buf_set_lines(self._bufnr, s, e, false, {})
end

function Buffer.set_to(self, window_id)
  vim.api.nvim_win_set_buf(window_id, self._bufnr)
end

function Buffer.cleanup(self)
  buffer_repository:delete(self._bufnr)
end

return M
