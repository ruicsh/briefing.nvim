-- Type annotations for busted/plenary test assertions
-- This file provides type hints for LuaLS to recognize assert methods
-- used in the test suite. It is NOT loaded at runtime.

---@class busted.assert.has_no
---@field errors fun(fn: fun()): any

---@class busted.assert
---@field equals fun(expected: any, actual: any): any
---@field same fun(expected: any, actual: any): any
---@field is_nil fun(value: any): any
---@field is_not_nil fun(value: any): any
---@field is_true fun(value: any): any
---@field is_false fun(value: any): any
---@field is_truthy fun(value: any): any
---@field has_no busted.assert.has_no
---@field is_not busted.assert

---Global assert extended with busted/plenary methods
---@type busted.assert
assert = {}
