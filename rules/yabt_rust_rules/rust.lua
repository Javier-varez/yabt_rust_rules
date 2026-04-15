local M = {}

local BIN_TYPE = 'bin'
local LIB_TYPE = 'lib'
local DEFAULT_EDITION = '2024'

---@param toolchain Toolchain
---@return BuildRule # Build rule for the given toolchain
local function rule_for_toolchain(toolchain, type)
    local crate_type
    local name_suffix
    if type == BIN_TYPE then
        crate_type = 'bin'
        name_suffix = 'rbin'
    elseif type == LIB_TYPE then
        crate_type = 'lib'
        name_suffix = 'rlib'
    end
    return {
        name = toolchain.name .. name_suffix,
        cmd = toolchain.rustc .. ' ' .. table.concat(toolchain.rustflags, ' ') ..
            '--out-dir $out_dir --edition $edition --crate-name $crate_name --crate-type ' ..
            crate_type .. ' $rustflags $src --emit dep-info,link',
        descr = 'rustc (toolchain: ' .. toolchain.name .. ') $target',
    }
end

---@param deps RustDep[]
local function collect_dependencies(toolchain, deps)
    local ninja_input_deps = {}
    local rustflags = ''

    ---@type RustLibrary[]
    local lib_queue = {}
    for _, dep in ipairs(deps) do
        table.insert(lib_queue, dep:rust_library(toolchain))
    end

    ---@type table<string, boolean>
    local handled = {}
    while #lib_queue > 0 do
        ---@type RustLibrary
        local lib = table.remove(lib_queue, 1)

        if not handled[lib.crate_name] then
            handled[lib.crate_name] = true

            table.insert(ninja_input_deps, lib:out_file())
            rustflags = rustflags .. ' --extern '.. lib.crate_name .. ' -L ' .. lib.out_dir:absolute()

            for _, dep in ipairs(lib.deps) do
                table.insert(lib_queue, dep:rust_library(toolchain))
            end
        end
    end

    return ninja_input_deps, rustflags
end

---@class RustDep
---@field rust_library fun(self: RustDep, toolchain: Toolchain): RustLibrary

---@class RustLibrary
---@field crate_name string
---@field out_dir OutPath
---@field src Path
---@field deps ?RustDep[]
---@field edition ?string        Defaults to 2024
---@field rustflags ?string[]
---@field toolchain ?Toolchain
local Library = {}

---@param lib RustLibrary
function Library:new(lib)
    setmetatable(lib, self)
    self.__index = self
    lib:resolve()
    return lib
end

-- Resolves the missing binary bits at lib declaration time
function Library:resolve()
    local selected_toolchain = require 'yabt_rust_rules.toolchain'.selected_toolchain()
    self.toolchain = self.toolchain or selected_toolchain
    self.rustflags = self.rustflags or {}
    self.deps = self.deps or {}

    local path = require 'yabt.core.path'
    if not path.is_out_path(self.out_dir) then
        error('Rust binary requires an output directory: ' .. type(self.src), 3)
    end

    if not path.is_path(self.src) then
        error('Rust binary requires a source file: ' .. type(self.src), 3)
    end

    if type(self.crate_name) ~= "string" or self.crate_name == '' then
        error('Rust binary requires a crate name', 3)
    end
end

---@return OutPath
function Library:out_file()
    return self.out_dir:join('lib' .. self.crate_name .. '.rlib')
end

---@param ctx Context
function Library:build(ctx)
    local out_file = self:out_file()
    local dep_file = self.out_dir:join(self.crate_name .. '.d')
    local ninja_input_deps, rustflags = collect_dependencies(self.toolchain, self.deps)
    table.insert(ninja_input_deps, self.src)

    for _, flag in ipairs(self.rustflags) do
        rustflags = rustflags .. ' ' .. flag
    end

    local build_rule = rule_for_toolchain(self.toolchain, LIB_TYPE)
    local build_step = {
        outs = { dep_file, out_file },
        ins = ninja_input_deps,
        rule_name = build_rule.name,
        variables = {
            edition = self.edition or DEFAULT_EDITION,
            crate_name = self.crate_name,
            out_dir = self.out_dir:absolute(),
            depfile = dep_file:absolute(),
            rustflags = rustflags,
            src = self.src:absolute(),
            target = out_file:absolute()
        }
    }
    ctx.add_build_step_with_rule(build_step, build_rule)
end

---@return RustLibrary
function Library:rust_library(toolchain)
    -- TODO: Use toolchain to generate a different lib for this toolchain. for this, the output dirs need namespacing
    return self
end

---@return RustLibrary
function Library:with_features(...)
    -- FIXME: Implement
    return self
end

---@class RustBinary
---@field crate_name string
---@field out_dir OutPath
---@field src Path
---@field deps RustDep[]
---@field edition ?string        Defaults to 2024
---@field rustflags ?string[]
---@field toolchain ?Toolchain
local Binary = {}

---@param bin RustBinary
function Binary:new(bin)
    setmetatable(bin, self)
    self.__index = self
    bin:resolve()
    return bin
end

-- Resolves the missing binary bits at lib declaration time
function Binary:resolve()
    local selected_toolchain = require 'yabt_rust_rules.toolchain'.selected_toolchain()
    self.toolchain = self.toolchain or selected_toolchain
    self.deps = self.deps or {}
    self.rustflags = self.rustflags or {}

    local path = require 'yabt.core.path'
    if not path.is_out_path(self.out_dir) then
        error('Rust binary requires an output directory: ' .. type(self.src), 3)
    end

    if not path.is_path(self.src) then
        error('Rust binary requires a source file: ' .. type(self.src), 3)
    end

    if type(self.crate_name) ~= "string" or self.crate_name == '' then
        error('Rust binary requires a crate name', 3)
    end
end

function Binary:out_file()
    return self.out_dir:join(self.crate_name)
end

---@param ctx Context
function Binary:build(ctx)
    local out_file = self:out_file()
    local dep_file = out_file:with_ext('d')
    local ninja_input_deps, rustflags = collect_dependencies(self.toolchain, self.deps)
    table.insert(ninja_input_deps, self.src)

    for _, flag in ipairs(self.rustflags) do
        rustflags = rustflags .. ' ' .. flag
    end

    local build_rule = rule_for_toolchain(self.toolchain, BIN_TYPE)
    local build_step = {
        outs = { dep_file, out_file },
        ins = ninja_input_deps,
        rule_name = build_rule.name,
        variables = {
            edition = self.edition or DEFAULT_EDITION,
            crate_name = self.crate_name,
            out_dir = self.out_dir:absolute(),
            depfile = dep_file:absolute(),
            rustflags = rustflags,
            src = self.src:absolute(),
            target = out_file:absolute()
        }
    }
    ctx.add_build_step_with_rule(build_step, build_rule)
end

function Binary:run(args)
    local out_file = self:out_file()
    local result = { out_file:absolute() }
    for _, arg in ipairs(args or {}) do
        table.insert(result, arg)
    end
    return result
end

M.Binary = Binary
M.Library = Library

return M
