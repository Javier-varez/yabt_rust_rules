local M = {}

---@class Toolchain
---@field name string
---@field rustc string
---@field rustflags string[]
---@field codegenopts ?{ [string]: string }

M._toolchains = {}
M._default_toolchain = nil

---@param toolchain Toolchain
function M.register_toolchain(toolchain)
    M._toolchains[toolchain.name] = toolchain
end

---@param toolchain Toolchain
function M.register_toolchain_as_default(toolchain)
    M._toolchains[toolchain.name] = toolchain
    M._default_toolchain = toolchain
end

function M.selected_toolchain()
    -- TODO: Once we have support for flags, return the selected toolchain instead of the default.
    return M._default_toolchain
end

function M.make_rustup_toolchain(channel)
    return {
        name = 'rustup-' .. channel,
        rustc = 'rustup run ' .. channel .. ' rustc',
        rustflags = {},
        codegenopts = {},
    }
end

M.register_toolchain_as_default(M.make_rustup_toolchain('stable'))

return M
