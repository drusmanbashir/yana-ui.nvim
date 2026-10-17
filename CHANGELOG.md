# Changelog

## 0.1.0-alpha.1 - 2026-10-17

- Retire grid input and rendering after native window or callback teardown.

### Current API

- Use LGPL-3.0-only for Qt-derived Lua; include LICENSE, COPYING, NOTICE,
  Qt rights-holder credits and SPDX/provenance headers. Preserve earlier
  valid Apache rights in original code; keep runtime behavior unchanged.
- Generate every public export’s reference from LuaCATS; run its example and
  the full docs gate.
- Use `yana_ui.grid` for columns/flowing cells, highlights, height limits,
  keyboard/mouse navigation and caller cancel/apply callbacks.
- Read extmark positions/ranges/groups with `yana_ui.paint`.
- Read window geometry/screen cells with `yana_ui.geometry`.
- Resolve screen coordinates and route hover/press with `yana_ui.input`.
