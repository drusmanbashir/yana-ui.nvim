-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS YSizePolicy: immutable Qt constraints, stored outside the value object.
---@alias YSizePolicyName "fixed"|"minimum"|"maximum"|"preferred"|"expanding"
---@class YSizePolicyOptions
---@field horizontal? YSizePolicyName [default: "preferred"] Horizontal policy.
---@field vertical? YSizePolicyName [default: "preferred"] Vertical policy.
---@field horizontal_stretch? integer [default: 0] Horizontal weight, 0 through 255.
---@field vertical_stretch? integer [default: 0] Vertical weight, 0 through 255.
---@class YSizePolicy
---@field horizontal_policy fun(self: YSizePolicy): YSizePolicyName Read the horizontal policy.
---@field vertical_policy fun(self: YSizePolicy): YSizePolicyName Read the vertical policy.
---@field horizontal_stretch fun(self: YSizePolicy): integer Read the horizontal weight.
---@field vertical_stretch fun(self: YSizePolicy): integer Read the vertical weight.
---@doc brief Store immutable per-axis sizing policies and stretch weights.
---@doc qt QSizePolicy. You get five policy names and two integer weights; there are no mutable flags, control types or height-for-width rules. fixed pins the hint, minimum sets a hint floor, maximum sets a hint ceiling, preferred permits resizing and expanding requests spare cells.
---@doc inherits none; this value has no parent, lifetime methods or signals.
---@doc property horizontal|horizontal_policy()|none|none|option:horizontal
---@doc property vertical|vertical_policy()|none|none|option:vertical
---@doc property horizontal_stretch|horizontal_stretch()|none|none|option:horizontal_stretch
---@doc property vertical_stretch|vertical_stretch()|none|none|option:vertical_stretch
---@doc errors Options must be a table. Policies require a listed name and stretches require integers from 0 through 255; invalid options raise assertions. Ordinary field assignment raises immutable YSizePolicy; create a new value to change a policy.
---@doc context lua/yana_ui/size_policy.lua|YSizePolicy
---@doc setup With your checkout on runtimepath, run this excerpt in Neovim. The value owns no native resources.
---@doc example local ui = require("yana_ui")
---@doc example local policy = ui.YSizePolicy.new({ horizontal = "expanding", horizontal_stretch = 2 })
---@doc example assert(policy:horizontal_policy() == "expanding")
---@doc example assert(policy:horizontal_stretch() == 2)
---@doc see |YBoxLayout|, |YWidget|.
local YSizePolicy = {}
local values = setmetatable({}, { __mode = "k" })
local names = { fixed = true, minimum = true, maximum = true, preferred = true, expanding = true }
local methods = {}
---Recognize a value allocated by this module.
---@param value any Value to inspect.
---@return boolean instance # Whether this is an allocated size policy.
function YSizePolicy.is_instance(value) return values[value] ~= nil end
---Create an immutable policy; omitted axes are preferred and omitted weights are zero.
---@param opts? YSizePolicyOptions [default: nil] Policy names and weights.
---@return YSizePolicy policy # New immutable value.
function YSizePolicy.new(opts)
  if opts == nil then opts = {} end
  assert(type(opts) == "table", "YSizePolicy options required")
  local h, v, hs, vs = opts.horizontal, opts.vertical, opts.horizontal_stretch, opts.vertical_stretch
  if h == nil then h = "preferred" end
  if v == nil then v = "preferred" end
  if hs == nil then hs = 0 end
  if vs == nil then vs = 0 end
  assert(names[h] and names[v], "invalid YSizePolicy name")
  for _, value in ipairs({ hs, vs }) do
    assert(type(value) == "number" and value >= 0 and value <= 255 and value == math.floor(value), "invalid YSizePolicy stretch")
  end
  local self = setmetatable({}, { __index = methods, __newindex = function() error("immutable YSizePolicy", 2) end })
  values[self] = { h, v, hs, vs }
  return self
end
---Read the stored horizontal policy.
---@return YSizePolicyName value # Horizontal policy name.
function methods:horizontal_policy() return values[self][1] end
---Read the stored vertical policy.
---@return YSizePolicyName value # Vertical policy name.
function methods:vertical_policy() return values[self][2] end
---Read the stored horizontal stretch.
---@return integer value # Horizontal stretch weight.
function methods:horizontal_stretch() return values[self][3] end
---Read the stored vertical stretch.
---@return integer value # Vertical stretch weight.
function methods:vertical_stretch() return values[self][4] end
-- DOCS: YSizePolicy example start
-- local ui = require("yana_ui")
-- local policy = ui.YSizePolicy.new({ horizontal = "expanding", horizontal_stretch = 2 })
-- assert(policy:horizontal_policy() == "expanding")
-- assert(policy:horizontal_stretch() == 2)
-- DOCS: YSizePolicy example end
return YSizePolicy
