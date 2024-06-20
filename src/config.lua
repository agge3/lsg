--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2023 Warner Losh <imp@bsdimp.com>
-- Copyright (c) 2024 Tyler Baxter <agge@FreeBSD.org>
--

-- Derived in large part from makesyscalls.lua:
--
-- SPDX-License-Identifier: BSD-2-Clause-FreeBSD
--
-- Copyright (c) 2019 Kyle Evans <kevans@FreeBSD.org>

-- Code to read in the config file that drives this. Since we inherit from the
-- FreeBSD makesyscall.sh legacy, all config is done through a config file that
-- sets a number of varibale (as noted below, it used to be a .sh file that was
-- sourced in. This dodges the need to write a command line parser.

-- XXX Not sure what else needs to be here, or if we should 'hoist' the merging of
-- the map this returns into the global config map since that's likely to be the
-- same everywhere.

-- xxx Getting closer to an answer to the above.

local config = {}

local util = require("util")

-- xxx To be added or deleted as necessary. Keeping here until decision is made.
config.obsol = {}
config.unimpl = {}
config.capenabled = {}
config.sys_no_abi_change = {}
config.sys_abi_change = {}
config.abi_flags = ""
config.compat_set = {}
local config_modified = {}
local cleantmp = true
-- local tmpspace = "/tmp/sysent." .. unistd.getpid() .. "/"

-- Important boolean keys: configuration file optionally specified and changes 
-- to the default ABI.
config.config_file = false
config.no_changes_abi = false
config.changes_abi = false or not config.no_changes_abi

-- Default configuration; any of these may get replaced by a configuration file
-- optionally specified.
config.default = {
    abi_func_prefix = "",
	abi_type_suffix = "",
    abi_intptr_t = "intptr_t",
}

-- Each entry should have a value so we can represent ABI flags as a bitmask
-- for convenience.  One may also optionally provide an expr; this gets applied
-- to each argument type to indicate whether this argument is subject to ABI
-- change given the configured flags.
config.known_abi_flags = {
	long_size = {
		value	= 0x00000001,
		exprs	= {
			"_Contains[a-z_]*_long_",
			"^long [a-z0-9_]+$",
			"long [*]",
			"size_t [*]",
			-- semid_t is not included because it is only used
			-- as an argument or written out individually and
			-- said writes are handled by the ksem framework.
			-- Technically a sign-extension issue exists for
			-- arguments, but because semid_t is actually a file
			-- descriptor negative 32-bit values are invalid
			-- regardless of sign-extension.
		},
	},
	time_t_size = {
		value	= 0x00000002,
		exprs	= {
			"_Contains[a-z_]*_timet_",
		},
	},
	pointer_args = {
		value	= 0x00000004,
	},
	pointer_size = {
		value	= 0x00000008,
		exprs	= {
			"_Contains[a-z_]*_ptr_",
			"[*][*]",
		},
	},
	pair_64bit = {
		value	= 0x00000010,
		exprs	= {
			"^dev_t[ ]*$",
			"^id_t[ ]*$",
			"^off_t[ ]*$",
		},
	},
}

-- config looks like a shell script; in fact, the previous makesyscalls.sh
-- script actually sourced it in.  It had a pretty common format, so we should
-- be fine to make various assumptions
function config.process(file)
	local cfg = {}
	local comment_line_expr = "^%s*#.*"
	-- We capture any whitespace padding here so we can easily advance to
	-- the end of the line as needed to check for any trailing bogus bits.
	-- Alternatively, we could drop the whitespace and instead try to
	-- use a pattern to strip out the meaty part of the line, but then we
	-- would need to sanitize the line for potentially special characters.
	local line_expr = "^([%w%p]+%s*)=(%s*[`\"]?[^\"`]*[`\"]?)"

	if not file then
		return nil, "No file given"
	end

	local fh = assert(io.open(file))

	for nextline in fh:lines() do
		-- Strip any whole-line comments
		nextline = nextline:gsub(comment_line_expr, "")
		-- Parse it into key, value pairs
		local key, value = nextline:match(line_expr)
		if key ~= nil and value ~= nil then
			local kvp = key .. "=" .. value
			key = util.trim(key)
			value = util.trim(value)
			local delim = value:sub(1,1)
			if delim == '"' then
				local trailing_context

				-- Strip off the key/value part
				trailing_context = nextline:sub(kvp:len() + 1)
				-- Strip off any trailing comment
				trailing_context = trailing_context:gsub("#.*$",
				    "")
				-- Strip off leading/trailing whitespace
				trailing_context = util.trim(trailing_context)
				if trailing_context ~= "" then
					print(trailing_context)
					abort(1, "Malformed line: " .. nextline)
				end

				value = util.trim(value, delim)
			else
				-- Strip off potential comments
				value = value:gsub("#.*$", "")
				-- Strip off any padding whitespace
				value = util.trim(value)
				if value:match("%s") then
					abort(1, "Malformed config line: " ..
					    nextline)
				end
			end
			cfg[key] = value
		elseif not nextline:match("^%s*$") then
			-- Make sure format violations don't get overlooked
			-- here, but ignore blank lines.  Comments are already
			-- stripped above.
			abort(1, "Malformed config line: " .. nextline)
		end
	end

	assert(io.close(fh))
	return cfg
end

-- Either returns nil and a message, or mutates cfg and cfg_mod based on the 
-- provided configuration file.
function config.mergeGlobal(fh, cfg, cfg_mod)
    if fh ~= nil then
    	local res = assert(config.process(fh))
    
    	for k, v in pairs(res) do
    		if v ~= cfg[k] then
    			cfg[k] = v
    			cfg_mod[k] = true
    		end
    	end
    end
end

-- xxx this needs to be reworked, we're not doing bitmasks anymore
function config.abiChanges(name)
    local abi_flags_mask = 0
	if config.known_abi_flags[name] == nil then
		util.abort(1, "abi_changes: unknown flag: " .. name)
	end

	return abi_flags_mask & config.known_abi_flags[name].value ~= 0
end

-- xxx these won't be necessary, but keeping for now
--function config.get_mask(flags)
--	local mask = 0
--	for _, v in ipairs(flags) do
--		if config.known_flags[v] == nil then
--			abort(1, "Checking for unknown flag " .. v)
--		end
--
--		mask = mask | known_flags[v]
--	end
--
--	return mask
--end
--
--function config.get_mask_pat(pflags)
--	local mask = 0
--	for k, v in pairs(config.known_flags) do
--		if k:find(pflags) then
--			mask = mask | v
--		end
--	end
--
--	return mask
--end

-- xxx probably should be in class syscall
--function config.global_abi_changes()
--    if config.changes_abi then
--    	-- argalias should be:
--    	--   COMPAT_PREFIX + ABI Prefix + funcname
--    	argprefix = config.abi_func_prefix
--    	funcprefix = config.abi_func_prefix
--    	funcalias = funcprefix .. funcname
--    	noproto = false
--    end
--end

-- xxx putting these here for now
--local function process_abi_flags()
--	local flags, mask = config.abi_flags, 0
--	for txtflag in flags:gmatch("([^|]+)") do
--		if known_abi_flags[txtflag] == nil then
--			abort(1, "Unknown abi_flag: " .. txtflag)
--		end
--
--		mask = mask | known_abi_flags[txtflag].value
--	end
--
--	config.abi_flags_mask = mask
--end
--
---- FOR changes_abi
--local function process_syscall_abi_change()
--	local changes_abi = config.syscall_abi_change
--	for syscall in changes_abi:gmatch("([^ ]+)") do
--		config.sys_abi_change[syscall] = true
--	end
--
--	local no_changes = config.syscall_no_abi_change
--	for syscall in no_changes:gmatch("([^ ]+)") do
--		config.sys_no_abi_change[syscall] = true
--	end
--end

return config
