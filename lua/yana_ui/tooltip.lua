-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS QToolTip: internal owner-cancelled native float; no focus or input owner.
local YObject = require("yana_ui.object")
local YTimer = require("yana_ui.timer")
local metrics = require("yana_ui.text_metrics")
local M, Tip = {}, setmetatable({}, { __index = YObject })
Tip.__index = Tip

function Tip:_close()
  local win,buf = self._win,self._buf
  self._win,self._buf = nil,nil
  if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win,true) end
  if buf and vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf,{force=true}) end
end
function Tip:cancel()
  self._timer:stop()
  self._widget,self._text = nil,nil
  self:_close()
end
function Tip:_valid()
  local widget = self._widget
  if self:is_destroyed() or not widget or widget:is_destroyed()
    or not widget:is_visible() or not widget:is_enabled() or vim.fn.pumvisible() == 1 then return false end
  local win,buf,generation = self._target()
  return win == self._target_win and buf == self._target_buf and generation == self._generation
    and self._valid_target() ~= false
end
function Tip:_show()
  if not self:_valid() then self:cancel(); return end
  local lines = vim.split(self._text,"\n",{plain=true})
  local width = 1
  for _,line in ipairs(lines) do width = math.max(width,metrics.width(line)) end
  width = math.max(1,math.min(width,vim.o.columns-2))
  local height = math.max(1,math.min(#lines,vim.o.lines-3))
  while #lines > height do table.remove(lines) end
  for i,line in ipairs(lines) do lines[i] = metrics.cell_clip(line,width) end
  local buf = vim.api.nvim_create_buf(false,true)
  vim.bo[buf].bufhidden, vim.bo[buf].filetype = "wipe", "yana-ui-tooltip"
  vim.api.nvim_buf_set_lines(buf,0,-1,false,lines)
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf,false,{relative="editor",style="minimal",border="single",
    row=math.min(self._screenrow,math.max(0,vim.o.lines-height-3)),
    col=math.min(self._screencol-1,math.max(0,vim.o.columns-width-2)),
    width=width,height=height,focusable=false,mouse=false,zindex=80})
  self._win,self._buf = win,buf
end
function Tip:consider(widget,pos)
  local win,buf,generation = self._target()
  if self._widget and (win ~= self._target_win or buf ~= self._target_buf or generation ~= self._generation) then
    self:cancel(); return "generation"
  end
  if not widget or widget:is_destroyed() or not widget:is_visible() or not widget:is_enabled()
    or type(widget.tooltip) ~= "function" or not pos or not self._valid_target()
    or vim.fn.pumvisible() == 1 then self:cancel(); return end
  local text,delay = widget:tooltip(),widget:tooltip_delay()
  if text == "" then self:cancel(); return end
  if self._widget == widget and self._text == text and self._delay == delay then
    if not self._win and (pos.screenrow ~= self._screenrow or pos.screencol ~= self._screencol) then
      self._screenrow,self._screencol = pos.screenrow,pos.screencol
      self._timer:start(delay)
    end
    return
  end
  self:cancel()
  self._widget,self._text,self._delay = widget,text,delay
  self._target_win,self._target_buf,self._generation = win,buf,generation
  self._screenrow,self._screencol = pos.screenrow,pos.screencol
  self._timer:bind(win,generation); self._timer:start(delay)
end
function M.new(opts)
  local self = setmetatable(YObject.new({parent=opts.parent}),Tip)
  self._target,self._valid_target = opts.current_target,opts.valid_target
  self._timer = YTimer.new({parent=self,single_shot=true,current_target=function()
    local win,_,generation = self._target(); return win,generation
  end})
  self._timer:connect("timeout",self,function(tip) tip:_show() end)
  self._autocmd = vim.api.nvim_create_autocmd({"WinClosed","BufWipeout","WinEnter","BufWinEnter","ModeChanged","CompleteChanged"}, {
    callback=function(event)
      if event.event == "ModeChanged" or event.event == "CompleteChanged" or not self:_valid() then self:cancel() end
    end,
  })
  return self
end
function Tip:_dispose()
  self:cancel()
  vim.api.nvim_del_autocmd(self._autocmd)
end
return M
