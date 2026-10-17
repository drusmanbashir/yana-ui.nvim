-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS Q0-E2: synthetic input shares native YEventDispatcher delivery.
local YObject = require("yana_ui.object")
---@class YTestInputOptions
---@field dispatcher YEventDispatcher [default: required] Live dispatcher you borrow for direct state tests.
--
---@class YTestInput
---@doc brief Send scalar test input through the public dispatcher.
---@doc qt QTest input helper. Calls are synchronous and synthetic; they prove state and callback order, not terminal delivery or visible pixels. key_click() sends one key event, not a press/release pair.
---@doc inherits none; this helper has no properties, signals or owned resources.
---@doc errors Coordinates and modifiers must be finite integers; invalid values raise assertions. Keys must be strings. Calls return false after the borrowed dispatcher is destroyed; no destruction reason is returned. Dispatcher and event callback errors propagate.
---@doc context lua/yana_ui/test_input.lua|YTestInput
---@doc setup Copy the Lua comments between the DOCS markers, remove their leading --, and run them in Neovim with yana-ui on runtimepath. You borrow the current window and buffer; the example owner releases its objects and mappings.
---@doc example local ui = require("yana_ui")
---@doc example local owner, win, buf = ui.YObject.new(), vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
---@doc example local target = function() return win, buf, 1 end
---@doc example local root = ui.YWidget.new({ parent = owner, event = function() return true end })
---@doc example local focus = ui.YFocus.new({ parent = owner, current_target = target })
---@doc example local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf,
---@doc example   generation = 1, current_target = target })
---@doc example local dispatcher = ui.YEventDispatcher.new({ parent = owner, root = root,
---@doc example   focus = focus, writer = writer, current_target = target })
---@doc example local layout = ui.YBoxLayout.new({ parent = owner })
---@doc example layout:add_widget(root); root:show(); layout:activate(0, 0, 8, 1, 1)
---@doc example focus:register(root, win, buf, 1)
---@doc example local input = ui.YTestInput.new({ dispatcher = dispatcher })
---@doc example input:move(0, 0); input:click(0, 0); input:key_click("<Space>")
---@doc example owner:destroy()
---@doc see |YEventDispatcher|.
local YTestInput = {}
YTestInput.__index = YTestInput
local function integer(value)
  assert(type(value) == "number" and value > -math.huge and value < math.huge
    and value == math.floor(value), "invalid input coordinate/modifiers")
end
---Borrow a live YObject with a dispatch method; invalid options or dispatcher
---values raise an assertion. The helper does not keep the dispatcher alive.
---@param opts YTestInputOptions Required dispatcher options.
---@return YTestInput input # Synthetic input helper.
function YTestInput.new(opts)
  assert(type(opts) == "table" and YObject.is_instance(opts.dispatcher)
    and not opts.dispatcher:is_destroyed() and type(opts.dispatcher.dispatch) == "function",
    "live YEventDispatcher required")
  return setmetatable({ _dispatcher = opts.dispatcher }, YTestInput)
end
function YTestInput:_deliver(kind, row, col, button, key, mods)
  if self._dispatcher:is_destroyed() then return false end
  return self._dispatcher:dispatch(kind, row, col, button, key, mods)
end
---Send one move event with button 0, an empty key and modifiers 0.
---@param row integer Zero-based canvas row; negative coordinates are allowed.
---@param col integer Zero-based canvas text-cell column; negative coordinates are allowed.
---@return boolean accepted # True if the final dispatched event is accepted; false if ignored or dispatcher dead.
function YTestInput:move(row, col)
  integer(row); integer(col)
  return self:_deliver("move", row, col, 0, "", 0)
end
---Send one left-button press with an empty key and modifiers 0.
---@param row integer Zero-based canvas row; negative coordinates are allowed.
---@param col integer Zero-based canvas text-cell column; negative coordinates are allowed.
---@return boolean accepted # True if the final dispatched event is accepted; false if ignored or dispatcher dead.
function YTestInput:press(row, col)
  integer(row); integer(col)
  return self:_deliver("press", row, col, 1, "", 0)
end
---Send one left-button release with an empty key and modifiers 0.
---@param row integer Zero-based canvas row; negative coordinates are allowed.
---@param col integer Zero-based canvas text-cell column; negative coordinates are allowed.
---@return boolean accepted # True if the final dispatched event is accepted; false if ignored or dispatcher dead.
function YTestInput:release(row, col)
  integer(row); integer(col)
  return self:_deliver("release", row, col, 1, "", 0)
end
---Send move, press and release in that order; return only release acceptance.
---@param row integer Zero-based canvas row; negative coordinates are allowed.
---@param col integer Zero-based canvas text-cell column; negative coordinates are allowed.
---@return boolean accepted # True if the final dispatched event is accepted; false if ignored or dispatcher dead.
function YTestInput:click(row, col)
  integer(row); integer(col)
  self:move(row, col); self:press(row, col)
  return self:release(row, col)
end
---Send one key event at row/column 0 with button 0. Key names are passed
---unchanged; this helper does not normalize them or replay ignored input.
---@param key string Dispatcher key name, for example "<Space>".
---@param mods? integer [default: 0] Finite modifier integer.
---@return boolean accepted # True when accepted; false if ignored or dispatcher dead.
function YTestInput:key_click(key, mods)
  assert(type(key) == "string", "invalid input key")
  if mods == nil then mods = 0 end
  integer(mods)
  return self:_deliver("key", 0, 0, 0, key, mods)
end
return YTestInput
-- DOCS: YTestInput example start
-- local ui = require("yana_ui")
-- local owner, win, buf = ui.YObject.new(), vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
-- local target = function() return win, buf, 1 end
-- local root = ui.YWidget.new({ parent = owner, event = function() return true end })
-- local focus = ui.YFocus.new({ parent = owner, current_target = target })
-- local writer = ui.YPaintWriter.new({ parent = owner, win = win, buf = buf,
--   generation = 1, current_target = target })
-- local dispatcher = ui.YEventDispatcher.new({ parent = owner, root = root,
--   focus = focus, writer = writer, current_target = target })
-- local layout = ui.YBoxLayout.new({ parent = owner })
-- layout:add_widget(root); root:show(); layout:activate(0, 0, 8, 1, 1)
-- focus:register(root, win, buf, 1)
-- local input = ui.YTestInput.new({ dispatcher = dispatcher })
-- input:move(0, 0); input:click(0, 0); input:key_click("<Space>")
-- owner:destroy()
-- DOCS: YTestInput example end
