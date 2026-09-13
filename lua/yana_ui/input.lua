local geometry = require("yana_ui.geometry")
local M = {}

local function resolve_hit(win, screen_row, screen_col, resolver)
  assert(type(resolver) == "function", "yana_ui.input resolver must be a function")
  local cell = geometry.cell(win, screen_row, screen_col)
  if not cell then return nil end
  local target = resolver(cell)
  if target == nil then return nil end
  return { target = target, cell = cell }
end

--- Resolve a screen coordinate through the caller's plugin-owned resolver.
function M.resolve(win, screen_row, screen_col, resolver)
  return resolve_hit(win, screen_row, screen_col, resolver)
end

local function drive(kind, win, screen_row, screen_col, resolver, handler)
  local hit = resolve_hit(win, screen_row, screen_col, resolver)
  if not hit then return nil end
  if handler then return handler(hit.target, hit.cell) end
  return hit.target
end

--- Resolve and dispatch a hover gesture through a caller-owned handler.
function M.hover(win, screen_row, screen_col, resolver, handler)
  return drive("hover", win, screen_row, screen_col, resolver, handler)
end

--- Resolve and dispatch a press gesture through a caller-owned handler.
function M.press(win, screen_row, screen_col, resolver, handler)
  return drive("press", win, screen_row, screen_col, resolver, handler)
end

return M
