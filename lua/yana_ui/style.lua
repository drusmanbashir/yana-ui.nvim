-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS S: native highlight descriptors, with state read from live owners.
local YPalette = require("yana_ui.palette")
local YWidget = require("yana_ui.widget")
local YObject = require("yana_ui.object")
---@alias YStyleRule {foreground_role: YPaletteRole|nil, background_role: YPaletteRole|nil, bold: boolean|nil, underline: boolean|nil}
---@alias YStyleRules table<string, table<YPaletteGroup, table<integer, YStyleRule>>>
---@class YStyleOptions
---@field palette? YPalette [default: YPalette.default()] Borrowed palette; changed role colors refresh this style.
---@field focus YFocus [default: required] Live focus owner supplying the current virtual target.
---@field rules? YStyleRules [default: nil] Explicit part/group/mask rules; nil generates button, item and tool_button rules for all six flags.
--
---@class YStyle
---@field enabled integer Read-only state flag: 1.
---@field mouse_over integer Read-only state flag: 0x2000.
---@field sunken integer Read-only state flag: 4.
---@field on integer Read-only state flag: 0x20.
---@field has_focus integer Read-only state flag: 0x100.
---@field selected integer Read-only state flag: 0x8000.
---@doc brief Resolve native highlight ids from live widget, focus and palette state.
---@doc qt QStyle. Six combinable flags and named parts replace Qt painting primitives. Default precedence is disabled, sunken, hovered/selected/on, then normal; focus underlines normal appearance. An idle tool_button omits its background.
---@doc inherits none; this value has no YObject lifetime or signals. Palette changes and ColorScheme refresh native descriptors and request updates on attached live widgets.
---@doc property palette|none|set_palette(palette)|none|option:palette
---@doc property rules|none|set_rules(rules)|none|option:rules
---@doc property tooltip_wake_up_delay|style_hint(name)|none|none|700 milliseconds
---@doc errors Invalid widgets, palettes, groups, masks, rules or hints raise assertions; checked, selected, bold and underline must be booleans when required. Masks are integers in 0..0xffff. Rule attributes are foreground_role, background_role, bold and underline only. Native API errors propagate. No style destruction method exists; you keep the borrowed focus owner valid while using it. Setters and attach() assert after that focus is destroyed. Native highlight slots are reused only after the focus and all attached widgets retire; live styles have exclusive mutable descriptors.
---@doc destroyed attach
---@doc exception attach() checks the widget lifetime, not a style destruction state; repeated attachment returns false without a reason.
---@doc context lua/yana_ui/style.lua|YStyle
---@doc setup Copy the Lua comments between the DOCS markers, remove their leading --, and run them in Neovim with yana-ui on runtimepath. You create an owner, its focus manager and one widget; the style borrows those objects and the shared default palette.
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new()
---@doc example local focus = ui.YFocus.new({ parent = owner })
---@doc example local style = ui.YStyle.new({ focus = focus })
---@doc example local widget = ui.YWidget.new({ parent = owner })
---@doc example style:attach(widget)
---@doc example local mask = style:state(widget, false, false)
---@doc example print(style:appearance("button", mask, "active"))
---@doc example print(style:style_hint("tooltip_wake_up_delay"))
---@doc example owner:destroy()
---@doc see |YPalette|, |YFocus|, |YWidget|.
local YStyle = { enabled = 1, mouse_over = 0x2000, sunken = 4,
  on = 0x20, has_focus = 0x100, selected = 0x8000 }
YStyle.__index = YStyle
local slots = {}
local groups = { active = true, inactive = true, disabled = true }
local instances = setmetatable({}, { __mode = "k" })
local function active(self)
  return not self._focus:is_destroyed() and slots[self._id] == self._slot
end
local function allocate(self)
  local id = 1
  while slots[id] do
    local slot = slots[id]
    local attached = false
    for widget in pairs(slot.widgets) do if not widget:is_destroyed() then attached=true;break end end
    if slot.focus:is_destroyed() and not attached then
      local former = slot.owner[1]
      if former then instances[former]=nil end
      break
    end
    id=id+1
  end
  local slot = {focus=self._focus,widgets=self._widgets,owner=setmetatable({self},{__mode="v"})}
  slots[id],self._id,self._slot = slot,id,slot
end
YStyle._grid_groups = { live = "YanaUiGridLive", dim = "YanaUiGridDim", flash = "YanaUiGridFlash",
  hover = "YanaUiGridHover", current = "YanaUiGridCurrent", marked = "YanaUiGridMarked", key = "YanaUiGridKey" }
YStyle._tab_groups = { normal = "YanaUiTabFill", active = "YanaUiTabActive", inactive = "YanaUiTabInactive",
  subtitle = "YanaUiTabStatus", button = "YanaUiTabButton", disabled = "YanaUiTabDisabled" }
local function prepare_tab_groups()
  local links = { normal = "TabLineFill", active = "TabLineSel", inactive = "TabLine",
    subtitle = "Comment", button = "TabLine", disabled = "Comment" }
  for role,name in pairs(YStyle._tab_groups) do vim.api.nvim_set_hl(0,name,{link=links[role],default=true}) end
end
local function prepare_grid_groups()
  local links = { live = "NormalFloat", dim = "Comment", flash = "IncSearch", hover = "Visual",
    current = "PmenuSel", marked = "Visual", key = "Special" }
  for role,name in pairs(YStyle._grid_groups) do vim.api.nvim_set_hl(0,name,{link=links[role],default=true}) end
end
prepare_grid_groups()
prepare_tab_groups()
local flag_values = { YStyle.enabled, YStyle.mouse_over, YStyle.sunken,
  YStyle.on, YStyle.has_focus, YStyle.selected }
local all_flags = 0
for _, flag in ipairs(flag_values) do all_flags = bit.bor(all_flags, flag) end
local function default_appearance(mask, group)
  if bit.band(mask, YStyle.enabled) == 0 or group == "disabled" then
    return "Comment", "button_text", "button", false
  end
  if bit.band(mask, YStyle.sunken) ~= 0 then
    return "IncSearch", "bright_text", "accent", false
  end
  if bit.band(mask, bit.bor(YStyle.mouse_over, YStyle.selected, YStyle.on)) ~= 0 then
    return "PmenuSel", "highlighted_text", "highlight", false
  end
  return "Pmenu", "button_text", "button", bit.band(mask, YStyle.has_focus) ~= 0
end
local function default_rules()
  local rules = { button = {}, item = {}, tool_button = {} }
  for part, values in pairs(rules) do
    for group in pairs(groups) do
      local masks = {}; values[group] = masks
      for n = 0, 63 do
        local mask = 0
        for i, flag in ipairs(flag_values) do
          if bit.band(n, bit.lshift(1, i - 1)) ~= 0 then mask = bit.bor(mask, flag) end
        end
        local _, fg, bg, underline = default_appearance(mask, group)
        if part == "tool_button" and group ~= "disabled" and bit.band(mask, YStyle.enabled) ~= 0
          and bit.band(mask, bit.bor(YStyle.mouse_over, YStyle.sunken, YStyle.on, YStyle.has_focus, YStyle.selected)) == 0 then
          bg = nil
        end
        masks[mask] = { foreground_role = fg, background_role = bg, underline = underline }
      end
    end
  end
  return rules
end
local function rules_copy(palette, rules)
  assert(type(rules) == "table", "YStyle rules required")
  local result = {}
  for part, values in pairs(rules) do
    assert(type(part) == "string" and part ~= "" and type(values) == "table", "invalid YStyle part")
    result[part] = {}
    for group, masks in pairs(values) do
      assert(groups[group] and type(masks) == "table", "invalid YStyle group")
      result[part][group] = {}
      for mask, rule in pairs(masks) do
        assert(type(mask) == "number" and mask >= 0 and mask <= 0xffff
          and mask == math.floor(mask) and type(rule) == "table", "invalid YStyle mask")
        local copy = {}
        for key, value in pairs(rule) do
          if key == "foreground_role" or key == "background_role" then
            palette:color(group, value)
          else
            assert(key == "bold" or key == "underline", "invalid YStyle attribute")
            YObject.boolean(value)
          end
          copy[key] = value
        end
        result[part][group][mask] = copy
      end
    end
  end
  return result
end
local decorations={'bold','italic','underline','undercurl','underdouble','underdotted','underdashed','strikethrough'}
local underlines={'underline','undercurl','underdouble','underdotted','underdashed'}
local function decorate(base,source)
  for _,key in ipairs(underlines)do
    if source[key]~=nil then for _,old in ipairs(underlines)do base[old]=nil end;break end
  end
  for _,key in ipairs(decorations)do if source[key]~=nil then base[key]=source[key]end end
end
local function refresh_overlay(self,entry)
  local attrs=vim.api.nvim_get_hl(0,{id=entry.base,link=false})
  local source=vim.api.nvim_get_hl(0,{name=entry.group,link=false})
  if source.fg~=nil then attrs[attrs.reverse and 'bg' or 'fg']=source.fg end
  if source.sp~=nil then attrs.sp=source.sp end
  decorate(attrs,source)
  if source.ctermfg~=nil then
    attrs[attrs.cterm and attrs.cterm.reverse and 'ctermbg' or 'ctermfg']=source.ctermfg
  end
  if source.cterm then attrs.cterm=attrs.cterm or {};decorate(attrs.cterm,source.cterm)end
  if not vim.deep_equal(attrs,entry.attrs)then
    vim.api.nvim_set_hl(0,entry.name,attrs);entry.attrs=attrs
  end
end
local function refresh_overlays(self)
  if not active(self)then return false end
  for _,entry in ipairs(self._overlay_entries)do refresh_overlay(self,entry)end
  return true
end
-- Internal presentation composition belongs to the existing live style slot.
function YStyle:_overlay(base,group)
  assert(active(self),'YStyle borrowed focus no longer valid')
  assert(type(base)=='number' and base>0 and base<math.huge and base==math.floor(base),'invalid base appearance')
  assert(type(group)=='string' and group~='' and not group:find('[\r\n%z]'),'invalid overlay group')
  local sources=self._overlays[base] or {};self._overlays[base]=sources
  local entry=sources[group]
  if not entry then
    local name='ToolkitStyle'..self._id..'_Overlay'..(#self._overlay_entries+1)
    entry={base=base,group=group,name=name,id=vim.api.nvim_get_hl_id_by_name(name)}
    sources[group]=entry;self._overlay_entries[#self._overlay_entries+1]=entry
  end
  refresh_overlay(self,entry);return entry.id
end
local function compile(self)
  if not active(self) then return false end
  for part, values in pairs(self._rules) do
    local descriptors = self._descriptors[part] or {}
    self._descriptors[part] = descriptors
    for group, masks in pairs(values) do
      descriptors[group] = descriptors[group] or {}
      for mask, rule in pairs(masks) do
        local name = "ToolkitStyle" .. self._id .. "_" .. part .. "_" .. group .. "_" .. mask
        local attrs = { bold = rule.bold, underline = rule.underline }
        local link = self._palette:_link(group, rule.foreground_role, rule.background_role)
        if self._defaults and link and not rule.bold and not rule.underline then attrs = { link = link }
        else
          if self._defaults then
            local source = default_appearance(mask, group)
            attrs = vim.api.nvim_get_hl(0, { name = source, link = false })
            if rule.underline then attrs.underline = true end
            if part == "tool_button" and rule.background_role == nil then attrs.bg = nil end
          end
          if rule.foreground_role then attrs.fg = self._palette:color(group, rule.foreground_role) end
          if rule.background_role then attrs.bg = self._palette:color(group, rule.background_role) end
        end
        vim.api.nvim_set_hl(0, name, attrs)
        descriptors[group][mask] = vim.api.nvim_get_hl_id_by_name(name)
      end
    end
  end
  refresh_overlays(self)
  self._revision = self._palette:revision()
  return true
end
local function invalidate(self)
  if not compile(self) then return end
  for widget in pairs(self._widgets) do
    if not widget:is_destroyed() then widget:update() end
  end
end
function YStyle._palette_changed(palette)
  for style in pairs(instances) do
    if style._palette == palette then invalidate(style) end
  end
end
local theme_pending=false
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ToolkitStyleTheme", { clear = true }),
  callback = function()
    prepare_grid_groups()
    prepare_tab_groups()
    for style in pairs(instances) do invalidate(style) end
    if not theme_pending then
      theme_pending=true
      vim.schedule(function()
        theme_pending=false
        for style in pairs(instances)do
          if refresh_overlays(style)then
            for widget in pairs(style._widgets)do if not widget:is_destroyed()then widget:update()end end
          end
        end
      end)
    end
  end,
})
---Compile native highlight descriptors and borrow the palette and live focus
---manager. Invalid or missing options and malformed rules raise assertions.
---No default YObject parent or destruction method is added.
---@param opts YStyleOptions Required focus and optional palette/rules.
---@return YStyle style # Compiled style value.
function YStyle.new(opts)
  assert(type(opts) == "table", "YStyle options required")
  local palette = opts.palette
  if palette == nil then palette = YPalette.default() end
  assert(YPalette.is_instance(palette), "invalid YStyle palette")
  assert(YObject.is_instance(opts.focus) and not opts.focus:is_destroyed()
    and type(opts.focus.focus_widget) == "function", "YStyle YFocus required")
  local defaults = opts.rules == nil
  local rules = rules_copy(palette, defaults and default_rules() or opts.rules)
  local self = setmetatable({ _palette = palette, _focus = opts.focus,
    _rules = rules, _descriptors = {}, _defaults = defaults,_overlays={},_overlay_entries={},
    _widgets = setmetatable({}, { __mode = "k" }) }, YStyle)
  allocate(self)
  compile(self)
  instances[self] = true
  return self
end
---Weakly attach a widget for repaint on palette, rules or theme changes.
---Invalid widget identities raise an assertion; dead widgets are refused.
---@param widget YWidget Widget whose update() to request on style invalidation.
---@return boolean attached # True for a new attachment; false if already attached or dead.
---@return "destroyed"|nil reason # Widget destruction refusal, or nil.
function YStyle:attach(widget)
  assert(active(self),"YStyle borrowed focus no longer valid")
  assert(YWidget.is_instance(widget), "YStyle YWidget required")
  if widget:is_destroyed() then return false, "destroyed" end
  if self._widgets[widget] then return false end
  self._widgets[widget] = true
  return true
end
---Read current enabled, pointer, pressed and focus state and combine it with
---your checked/selected values. Invalid widgets or non-boolean state arguments
---raise assertions; checked is not inferred from a YAction.
---@param widget YWidget Widget providing current state.
---@param checked boolean Checked state supplied by the control or action.
---@param selected boolean Selection state supplied by the control.
---@return integer mask # Combined enabled, mouse_over, sunken, on, has_focus and selected flags.
function YStyle:state(widget, checked, selected)
  assert(YWidget.is_instance(widget), "YStyle YWidget required")
  YObject.boolean(checked); YObject.boolean(selected)
  local mask = 0
  if widget:is_enabled() then mask = bit.bor(mask, YStyle.enabled) end
  if widget:under_mouse() then mask = bit.bor(mask, YStyle.mouse_over) end
  if widget:is_pressed() then mask = bit.bor(mask, YStyle.sunken) end
  if checked then mask = bit.bor(mask, YStyle.on) end
  if selected then mask = bit.bor(mask, YStyle.selected) end
  if self._focus:focus_widget() == widget then mask = bit.bor(mask, YStyle.has_focus) end
  return mask
end
---Resolve a native highlight id, falling back to mask zero for the chosen
---part/group. A mask without enabled always selects disabled. Default rules
---strip unrelated bits; explicit rules retain them. Invalid arguments raise
---assertions; missing part/group/mask descriptors return nil.
---@param part string Rule part, for example "button", "item" or "tool_button".
---@param mask integer State flags in 0..0xffff.
---@param group YPaletteGroup Requested color group; disabled state overrides it.
---@return integer|nil appearance # Native highlight group id, or nil without a descriptor.
function YStyle:appearance(part, mask, group)
  assert(type(part) == "string" and type(mask) == "number" and mask >= 0
    and mask <= 0xffff and mask == math.floor(mask) and groups[group], "invalid appearance")
  if bit.band(mask, YStyle.enabled) == 0 then group = "disabled" end
  if self._defaults then mask = bit.band(mask, all_flags) end
  local values = self._descriptors[part]
  values = values and values[group]
  return values and (values[mask] or values[0]) or nil
end
---Read the implemented tooltip delay hint. Other names raise an assertion.
---@param name "tooltip_wake_up_delay" Supported hint name.
---@return integer milliseconds # Always 700.
function YStyle:style_hint(name)
  assert(name == "tooltip_wake_up_delay", "unknown YStyle hint")
  return 700
end
---Borrow another palette, recompile descriptors and request attached widget
---updates. Invalid palette identities raise an assertion; the same palette
---identity changes nothing.
---@param palette YPalette Palette to borrow.
---@return boolean changed # True when replaced; false for the same palette.
function YStyle:set_palette(palette)
  assert(active(self),"YStyle borrowed focus no longer valid")
  assert(YPalette.is_instance(palette), "invalid YStyle palette")
  if self._palette == palette then return false end
  self._palette = palette; invalidate(self)
  return true
end
---Validate and copy explicit rules, recompile descriptors and request attached
---widget updates. Invalid rules raise before replacement. Equal rules change
---nothing; a changed rule set turns off generated default-rule behavior.
---@param rules YStyleRules Explicit part/group/mask rules.
---@return boolean changed # True when replaced; false for equal rules.
function YStyle:set_rules(rules)
  assert(active(self),"YStyle borrowed focus no longer valid")
  local copied = rules_copy(self._palette, rules)
  if vim.deep_equal(copied, self._rules) then return false end
  self._rules, self._descriptors, self._defaults = copied, {}, false
  invalidate(self)
  return true
end
return YStyle
-- DOCS: YStyle example start
-- local ui = require("yana_ui")
-- local owner = ui.YObject.new()
-- local focus = ui.YFocus.new({ parent = owner })
-- local style = ui.YStyle.new({ focus = focus })
-- local widget = ui.YWidget.new({ parent = owner })
-- style:attach(widget)
-- local mask = style:state(widget, false, false)
-- print(style:appearance("button", mask, "active"))
-- print(style:style_hint("tooltip_wake_up_delay"))
-- owner:destroy()
-- DOCS: YStyle example end
