-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS C/Q0: role values, live theme bindings and one default palette.
---@alias YPaletteGroup "active"|"inactive"|"disabled"
---@alias YPaletteRole "window_text"|"button"|"light"|"midlight"|"dark"|"mid"|"text"|"bright_text"|"button_text"|"base"|"window"|"shadow"|"highlight"|"highlighted_text"|"link"|"link_visited"|"alternate_base"|"no_role"|"tooltip_base"|"tooltip_text"|"placeholder_text"|"accent"
---@class YPaletteOptions
---@field theme? "native"|"dark"|"light" [default: native without colors] Named palette; cannot be combined with colors. Native follows the editor; dark/light supply fixed RGB roles.
---@field colors? table<YPaletteGroup,table<YPaletteRole,integer>> [default: nil] An explicit table supplies sparse RGB values without theme fallback; omit to use the selected theme.
--
---@class YPalette
---@doc brief Select native, dark or light theme colors, or supply sparse RGB roles.
---@doc qt QPalette. Three groups and integer RGB roles replace Qt brushes. Native roles read Pmenu, PmenuSel, IncSearch, Special, Comment and FloatBorder; disabled text/button/base roles use Comment. Dark/light have fixed RGB roles. no_role has no color.
---@doc inherits none; this value has no YObject lifetime or signals.
---@doc property colors|color(group, role)|set_color(group, role, color)|none|option:colors
---@doc property revision|revision()|none|none|0
---@doc errors Unknown themes, combined theme/colors, unknown groups or roles and non-integer RGB values outside 0..0xffffff raise assertions. There are no destruction returns. Native theme changes are read live and do not increment revision; explicit changed colors increment it and refresh attached styles.
---@doc context lua/yana_ui/palette.lua|YPalette
---@doc setup Copy the Lua comments between the DOCS markers, remove their leading --, and run them in Neovim with yana-ui on runtimepath. You create an independent palette; it owns no native resources.
---@doc example local ui = require("yana_ui")
---@doc example local palette = ui.YPalette.new({ colors = { active = {
---@doc example   button_text = 0xffffff, button = 0x202020,
---@doc example } } })
---@doc example palette:set_color("active", "button", 0x303030)
---@doc example print(palette:color("active", "button"), palette:revision())
---@doc see |YStyle|, |nvim_get_hl()|.
local YPalette = {}
YPalette.__index = YPalette
local instances = setmetatable({}, { __mode = "k" })
local groups = { active = true, inactive = true, disabled = true }
local roles = {}
for role in ("window_text button light midlight dark mid text bright_text button_text base window shadow highlight highlighted_text link link_visited alternate_base no_role tooltip_base tooltip_text placeholder_text accent"):gmatch("%S+") do
  roles[role] = true
end
local bindings = {
  button_text = { "Pmenu", "fg" }, button = { "Pmenu", "bg" },
  text = { "Pmenu", "fg" }, base = { "Pmenu", "bg" },
  window_text = { "Pmenu", "fg" }, window = { "Pmenu", "bg" },
  highlighted_text = { "PmenuSel", "fg" }, highlight = { "PmenuSel", "bg" },
  bright_text = { "IncSearch", "fg" }, accent = { "IncSearch", "bg" },
  link = { "Special", "fg" }, link_visited = { "Special", "fg" },
  placeholder_text = { "Comment", "fg" }, alternate_base = { "Pmenu", "bg" },
  tooltip_text = { "Pmenu", "fg" }, tooltip_base = { "Pmenu", "bg" },
  light = { "FloatBorder", "fg" }, midlight = { "FloatBorder", "fg" },
  dark = { "FloatBorder", "fg" }, mid = { "FloatBorder", "fg" },
  shadow = { "FloatBorder", "bg" },
}
local disabled = {
  button_text = true, text = true, window_text = true, highlighted_text = true,
  button = true, base = true,
}
local default_palette
local themes = {
  dark = { fg = 0xabb2bf, bg = 0x21252b, button = 0x282c34, disabled = 0x7f848e,
    highlight = 0x3e4451, accent = 0xe5c07b, accent_text = 0x21252b,
    link = 0x61afef, visited = 0xc678dd, border = 0x5c6370, alternate = 0x2c313a },
  light = { fg = 0x24292f, bg = 0xffffff, button = 0xe5e7eb, disabled = 0x6e7781,
    highlight = 0xcce5ff, accent = 0x8250df, accent_text = 0xffffff,
    link = 0x0969da, visited = 0x8250df, border = 0x57606a, alternate = 0xf6f8fa },
}
local function theme_colors(name)
  local p = themes[name]
  local active = { window_text = p.fg, button_text = p.fg, text = p.fg,
    window = p.bg, base = p.bg, button = p.button, shadow = p.bg,
    highlighted_text = p.fg, highlight = p.highlight, bright_text = p.accent_text,
    accent = p.accent, link = p.link, link_visited = p.visited,
    placeholder_text = p.disabled, alternate_base = p.alternate,
    tooltip_text = p.fg, tooltip_base = p.button,
    light = p.border, midlight = p.border, dark = p.border, mid = p.border }
  local disabled_colors = vim.deepcopy(active)
  for role in pairs(disabled) do
    disabled_colors[role] = role:find('text') and p.disabled or p.button
  end
  return { active = active, inactive = vim.deepcopy(active), disabled = disabled_colors }
end
local function validate(group, role, color)
  assert(groups[group], "invalid YPalette group")
  assert(roles[role], "invalid YPalette role")
  if color ~= nil then
    assert(type(color) == "number" and color >= 0 and color <= 0xffffff and color == math.floor(color), "invalid RGB")
  end
end
---Recognize a value allocated by YPalette.new(); other values are allowed.
---@param value any Value to inspect.
---@return boolean instance # True for an allocated palette.
function YPalette.is_instance(value) return instances[value] == true end
---Select a named theme, copy supplied sparse colors, or use the native default.
---Invalid option tables, group tables or RGB values raise assertions.
---@param opts? YPaletteOptions [default: nil] Palette options.
---@return YPalette palette # Independent palette with revision zero.
function YPalette.new(opts)
  if opts == nil then opts = {} end
  assert(type(opts) == "table", "YPalette options required")
  assert(opts.colors == nil or type(opts.colors) == "table", "invalid YPalette colors")
  assert(opts.theme == nil or opts.theme == "native" or themes[opts.theme], "invalid YPalette theme")
  assert(opts.theme == nil or opts.colors == nil, "YPalette theme and colors are mutually exclusive")
  local name = opts.theme or (opts.colors ~= nil and "custom" or "native")
  local supplied = themes[name] and theme_colors(name) or opts.colors
  local colors = { active = {}, inactive = {}, disabled = {} }
  for group, values in pairs(supplied or {}) do
    assert(groups[group] and type(values) == "table", "invalid YPalette group")
    for role, color in pairs(values) do validate(group, role, color); colors[group][role] = color end
  end
  local self = setmetatable({ _colors = colors, _revision = 0,
    _theme = name == "native", _theme_name = name }, YPalette)
  instances[self] = true
  return self
end
---Read the palette's original preset name. Explicit colors report custom;
---set_color overrides retain the original name.
---@return "native"|"dark"|"light"|"custom" name # Source of this palette.
function YPalette:theme_name() return self._theme_name end
---Read the shared theme-backed palette, creating it on first use. Color
---overrides you set here are visible to all styles borrowing this palette.
---@return YPalette palette # Shared default palette.
function YPalette.default()
  if not default_palette then default_palette = YPalette.new() end
  return default_palette
end
function YPalette:_source(group, role)
  if not self._theme or self._colors[group][role] ~= nil then return nil end
  local binding = bindings[role]
  if not binding then return nil end
  if group == "disabled" and disabled[role] then return "Comment", binding[2] end
  return binding[1], binding[2]
end
---Read an override, then the theme binding if enabled. Unspecified explicit
---roles, no_role and theme attributes without a color return nil.
---@param group YPaletteGroup Color group.
---@param role YPaletteRole Color role.
---@return integer|nil color # RGB value, or nil when unavailable.
function YPalette:color(group, role)
  validate(group, role)
  local value = self._colors[group][role]
  if value ~= nil then return value end
  local name, attribute = self:_source(group, role)
  if name then return vim.api.nvim_get_hl(0, { name = name, link = false })[attribute] end
end
function YPalette:_link(group, foreground, background)
  if not foreground or not background then return nil end
  local fg, fa = self:_source(group, foreground)
  local bg, ba = self:_source(group, background)
  if fg and fg == bg and fa == "fg" and ba == "bg" then return fg end
end
---Set an RGB override. A value equal to the resolved color changes nothing;
---a change increments revision before attached styles refresh. Nil raises an
---assertion; overrides cannot be cleared through this method.
---@param group YPaletteGroup Color group.
---@param role YPaletteRole Color role.
---@param color integer RGB value in 0..0xffffff.
---@return boolean changed # True on change; false when the resolved value matches.
function YPalette:set_color(group, role, color)
  validate(group, role, color); assert(color ~= nil, "RGB required")
  if self:color(group, role) == color then return false end
  self._colors[group][role], self._revision = color, self._revision + 1
  local style = package.loaded["yana_ui.style"]
  if style then style._palette_changed(self) end
  return true
end
---Read the count of changed explicit colors; ColorScheme does not change it.
---@return integer revision # Monotonically increasing revision.
function YPalette:revision() return self._revision end
return YPalette
-- DOCS: YPalette example start
-- local ui = require("yana_ui")
-- local palette = ui.YPalette.new({ colors = { active = {
--   button_text = 0xffffff, button = 0x202020,
-- } } })
-- palette:set_color("active", "button", 0x303030)
-- print(palette:color("active", "button"), palette:revision())
-- DOCS: YPalette example end
