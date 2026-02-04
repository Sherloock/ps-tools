-- Example WezTerm config: use PowerShell so your profile and ps-tools loader run.
-- Copy to %USERPROFILE%\.wezterm.lua for global use, or keep as .wezterm.lua
-- in this repo and set WEZTERM_CONFIG_FILE when starting WezTerm from here.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.default_prog = { 'powershell.exe', '-NoLogo' }
-- Or PowerShell Core: config.default_prog = { 'pwsh.exe', '-NoLogo' }

return config
