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

local util = require("util")

-- 
-- Global config map.
-- Default configuration is amd64 native. Any of these may get replaced by a 
-- configuration file optionally specified. 
--
config = {
    sysnames = "syscalls.c",
    sysproto = "sysproto.h",
    sysproto_h = "_SYS_SYSPROTO_H_",
    syshdr = "syscall.h",
    syssw = "init_sysent.c",
    syscallprefix = "SYS_",
    switchname = "sysent",          -- xxx 
    namesname = "syscallnames",     -- xxx
    abi_flags = {},
    abi_func_prefix = "",
    abi_type_suffix = "",
    abi_long = "long",
    abi_u_long = "u_long",
    abi_semid_t = "semid_t",
    abi_size_t = "size_t",
    abi_ptr_array_t = "",
    abi_headers = "",
    abi_intptr_t = "intptr_t",
    ptr_intptr_t_cast = "intptr_t",
    syscall_abi_change = {},        -- System calls that require ABI-specific handling
    syscall_no_abi_change = {},     -- System calls that appear to require handling, but don't
    -- xxx why don't we just set these tables below when we merge?
    obsol = {},     -- OBSOL system calls
    unimpl = {},    -- System calls without implementations
    capabilities_conf = "capabilities.conf",
    compat_set = "native",
    mincompat = 0,
    capenabled = {},
}

-- Keep track of modifications if there are.
config.mod = {}

-- Important boolean keys: file, changes to the ABI, or no changes to the ABI. 
config.file = false
config.no_changes_abi = false
config.changes_abi = false or not config.no_changes_abi

-- For each entry, the ABI flag is the key. One may also optionally provide an 
-- expr, which are contained in an array associated with each key; expr gets 
-- applied to each argument type to indicate whether this argument is subject to 
-- ABI change given the configured flags.
config.known_abi_flags = {
	long_size = {
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
	time_t_size = {
		"_Contains[a-z_]*_timet_",
	},
	pointer_args = {
        -- no expr
	},
	pointer_size = {
		"_Contains[a-z_]*_ptr_",
		"[*][*]",
	},
	pair_64bit = {
		"^dev_t[ ]*$",
		"^id_t[ ]*$",
		"^off_t[ ]*$",
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

-- Merges processed configuration file into the global config map (see above),
-- or returns NIL and a message.
function config.merge(fh)
    if fh ~= nil then
    	local res = assert(config.process(fh))
    
    	for k, v in pairs(res) do
    		if v ~= config[k] then
                -- handling of sets
                -- xxx haven't tested implementation, but you get the idea
                if v:find("abi_flags") then
                    -- match for pipe, that's how abi_flags is formatted
                    table.insert(config[k], util.setFromString(v, "[^|]+"))
                elseif v:find("capenabled") or
                        v:find("syscall_abi_change") or
                        v:find("syscall_no_abi_change") or
                        v:find("obsol") or
                        v:find("unimpl") then
                    -- match for space, that's how these are formatted
                    table.insert(config[k], util.setFromString(v, "[^ ]+"))
                else
    			    config[k] = v
                end
    			mod[k] = true
    		end
    	end
    end
end

-- Returns TRUE if there are ABI changes from native for the provided ABI flag. 
-- xxx test in interpreter, lua indexing has a lot of semantics
function config.abiChanges(name)
	if config.known_abi_flags[name] == nil then
		util.abort(1, "abi_changes: unknown flag: " .. name)
	end
    return config.abi_flags[name] ~= nil
end

-- xxx for myself, haven't found the relevancy yet
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

return config
