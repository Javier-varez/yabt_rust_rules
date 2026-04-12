local M = {}

---@param toolchain Toolchain
---@return BuildRule # Build rule for the given toolchain
local function bin_rule_for_toolchain(toolchain)
    return {
        name = toolchain.name .. '-rbin',
        cmd = toolchain.rustc .. ' ' .. table.concat(toolchain.rustflags, ' ') ..
            '--out-dir $out_dir --edition $edition --crate-name $crate_name --crate-type bin $in --emit dep-info,link',
        descr = 'rustc (toolchain: ' .. toolchain.name .. ') $out',
    }
end

---@class Binary
---@field crate_name string
---@field out_dir OutPath
---@field src Path
---@field edition string
---@field rustflags ?string[]
---@field toolchain ?Toolchain
local Binary = {}

---@param bin Binary
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

---@param ctx Context
function Binary:build(ctx)
    local ins = { self.src }
    local build_rule = bin_rule_for_toolchain(self.toolchain)
    local out_file = self.out_dir:join(self.crate_name)
    local dep_file = out_file:with_ext('d')
    local build_step = {
        outs = { dep_file, out_file },
        ins = ins,
        rule_name = build_rule.name,
        variables = {
            edition = self.edition or '2024',
            crate_name = self.crate_name,
            out_dir = self.out_dir:absolute(),
            depfile = dep_file:absolute(),
        }
    }
    ctx.add_build_step_with_rule(build_step, build_rule)
end

function Binary:run(args)
    local result = { self.out:absolute() }
    for _, arg in ipairs(args or {}) do
        table.insert(result, arg)
    end
    return result
end

M.Binary = Binary

return M
