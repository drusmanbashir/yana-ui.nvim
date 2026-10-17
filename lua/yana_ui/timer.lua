-- SPDX-FileCopyrightText: 2026 Usman Bashir
-- SPDX-License-Identifier: LGPL-3.0-only
-- WIDGETS Stage2: actual uv scheduling; lifetime/target validation on delivery.
local YObject = require("yana_ui.object")
---@class YTimerOptions : YObjectOptions
---@field parent YObject Required live owner; destroying it stops and closes the timer.
---@field interval? integer [default: 0] Integer milliseconds <=2147483647; negative values warn and become 1.
---@field single_shot? boolean [default: false] Stop before delivering the first timeout.
---@field current_target? fun(): integer, integer [default: nil] Returns current target id and generation for delivery checks; use bind() to set the expected pair.
---@class YTimer : YObject
---@doc brief A parent-owned native timer with scheduled, identity-checked timeout delivery.
---@doc qt QTimer. vim.uv measures elapsed time and vim.schedule() delivers callbacks in Neovim. There is no Qt timer type or precision setting; delayed repeats deliver once and restart from delivery rather than replaying missed ticks.
---@doc inherits |YObject|; inherited methods and destroyed retain |YObject| semantics. Unlike YObject.new(), this constructor requires a live parent.
---@doc property interval|interval()|set_interval(value), start(value)|none|option:interval
---@doc property active|is_active()|start(value), stop()|none|false
---@doc property single_shot|none|set_single_shot(value)|none|option:single_shot
---@doc property target|none|bind(id, generation)|none|nil, nil (unbound)
---@signal timeout() | Emitted on the Neovim main loop after lifetime, restart identity and optional current_target checks. Single-shot becomes inactive before delivery; repeating timers rearm before delivery. A stale target stops the timer without emitting.
---@doc errors Intervals must be finite integers <=2147483647; negative values warn and become 1 ms. Boolean options/setters require booleans. These validations raise before the destroyed check. Callback errors propagate; getters remain readable after destruction, with active=false.
---@doc destroyed set_interval,set_single_shot,bind,start,stop
---@doc context lua/yana_ui/timer.lua|YTimer
---@doc setup Run this block in Neovim with yana-ui on runtimepath. It needs no native window/buffer, waits for a real single-shot timeout, and destroys its owner.
-- DOCS: YTimer example start
---@doc example local ui = require("yana_ui")
---@doc example local owner = ui.YObject.new()
---@doc example local id, generation = 1, 1
---@doc example local timer = ui.YTimer.new({ parent = owner, interval = 1, single_shot = true,
---@doc example   current_target = function() return id, generation end })
---@doc example local fired = false
---@doc example timer:connect("timeout", owner, function() fired = true end)
---@doc example assert(timer:bind(id, generation)); assert(timer:start())
---@doc example local delivered = vim.wait(1000, function() return fired end)
---@doc example owner:destroy()
---@doc example assert(delivered and not timer:is_active())
-- DOCS: YTimer example end
---@doc see |YObject|, |vim.uv|, |vim.schedule()|.
local YTimer = setmetatable({}, { __index = YObject })
YTimer.__index = YTimer
local uv = vim.uv
local function interval(value)
  assert(type(value) == "number" and value == math.floor(value) and value <= 2147483647
    and value > -math.huge, "interval must be integer milliseconds <=2147483647")
  if value < 0 then
    vim.notify("yana-ui YTimer: negative interval becomes 1 ms", vim.log.levels.WARN)
    return 1
  end
  return value
end

local function arm(self)
  local remaining = math.max(0, math.ceil((self._deadline - uv.hrtime()) / 1000000))
  self._native:start(remaining, 0, self._native_callback)
end

local function native_timeout(self)
  if self:is_destroyed() or not self._active then return end
  local parent = self:parent()
  if parent and parent:is_destroyed() then return end
  if uv.hrtime() < self._deadline then arm(self); return end
  self._due_epoch = self._epoch
  if not self._queued then
    self._queued = true
    vim.schedule(self._delivery_callback)
  end
end

local function deliver(self)
  self._queued = false
  local epoch = self._due_epoch
  self._due_epoch = nil
  if self:is_destroyed() or not self._active or epoch ~= self._epoch then return end
  local parent = self:parent()
  if parent and parent:is_destroyed() then self:stop(); return end
  if self._current_target then
    local id, generation = self._current_target()
    if id ~= self._target_id or generation ~= self._generation then self:stop(); return end
  end
  if uv.hrtime() < self._deadline then arm(self); return end
  if self._single_shot then self._active = false
  else
    -- Restart from delivery, so an overrun generates one timeout, never a backlog.
    self._deadline = uv.hrtime() + self._interval * 1000000
    arm(self)
  end
  self:emit("timeout")
end

---Allocate an inactive uv timer. Missing/dead parents, non-table options,
---non-function current_target or failure to allocate a native timer raise.
---@param opts YTimerOptions Required constructor options.
---@return YTimer timer # New inactive timer.
function YTimer.new(opts)
  assert(type(opts) == "table" and YObject.is_instance(opts.parent)
    and not opts.parent:is_destroyed(), "YTimer requires a live parent YObject")
  assert(opts.current_target == nil or type(opts.current_target) == "function",
    "current_target must be a function")
  local ms = interval(opts.interval == nil and 0 or opts.interval)
  if opts.single_shot ~= nil then YObject.boolean(opts.single_shot) end
  local native = assert(uv.new_timer(), "cannot create uv timer")
  local self = setmetatable(YObject.new(opts), YTimer)
  self._native, self._interval, self._single_shot = native, ms, opts.single_shot == true
  self._current_target, self._epoch, self._active = opts.current_target, 0, false
  self._native_callback = function() native_timeout(self) end
  self._delivery_callback = function() deliver(self) end
  return self
end

---Read the stored, normalized interval in milliseconds.
---@return integer milliseconds # Nonnegative interval.
function YTimer:interval() return self._interval end
---Read whether the timer is started and awaiting or repeating delivery.
---@return boolean active # False after stop, single-shot delivery or destruction.
function YTimer:is_active() return self._active end

---Store a normalized interval; changing it restarts an active timer and
---invalidates any previously queued timeout. An unchanged value does nothing.
---@param value integer Interval in milliseconds.
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YTimer:set_interval(value)
  local ms = interval(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._interval == ms then return false end
  self._interval = ms
  if self._active then self:start() end
  return true
end

---Change the mode used by the next delivery without restarting the timer.
---@param value boolean True delivers only once per start().
---@return boolean changed # True on change; false if unchanged or destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YTimer:set_single_shot(value)
  YObject.boolean(value)
  if self:is_destroyed() then return false, "destroyed" end
  if self._single_shot == value then return false end
  self._single_shot = value
  return true
end

---Set the expected target pair. A different pair stops an active timer;
---the same pair leaves it running. Id must be a positive finite integer and
---generation a nonnegative finite integer; invalid values raise before the
---destroyed check. This comparison is used only with current_target supplied.
---@param id integer Expected positive target id.
---@param generation integer Expected nonnegative target generation.
---@return boolean bound # True even for an unchanged pair; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YTimer:bind(id, generation)
  assert(type(id) == "number" and id > 0 and id < math.huge and id == math.floor(id), "invalid target id")
  assert(type(generation) == "number" and generation >= 0 and generation < math.huge
    and generation == math.floor(generation),
    "invalid target generation")
  if self:is_destroyed() then return false, "destroyed" end
  if self._target_id ~= id or self._generation ~= generation then self:stop() end
  self._target_id, self._generation = id, generation
  return true
end

---Start or restart, invalidating queued delivery from an earlier start.
---Supplying an interval also stores it; zero schedules the earliest available
---delivery, without a synchronous timeout callback.
---@param value? integer [default: current interval] Replacement interval in milliseconds.
---@return boolean started # True after arming; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YTimer:start(value)
  local ms = value == nil and self._interval or interval(value)
  if self:is_destroyed() then return false, "destroyed" end
  self._native:stop()
  self._interval, self._epoch, self._due_epoch = ms, self._epoch + 1, nil
  self._active, self._deadline = true, uv.hrtime() + ms * 1000000
  arm(self)
  return true
end

---Stop native scheduling and invalidate queued delivery; an already stopped
---live timer still succeeds.
---@return boolean stopped # True when live; false if destroyed.
---@return "destroyed"|nil reason # "destroyed" when dead; nil otherwise.
function YTimer:stop()
  if self:is_destroyed() then return false, "destroyed" end
  self._active, self._due_epoch, self._epoch = false, nil, self._epoch + 1
  self._native:stop()
  return true
end

function YTimer:_dispose()
  self._active, self._due_epoch, self._epoch = false, nil, self._epoch + 1
  self._native:stop()
  self._native:close()
end

return YTimer
