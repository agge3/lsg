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

-- class scarg provides an interface for syscall arguments, in the parsing state.

local config = require("config")
local util = require("util")

local scarg = {}

scarg.__index = scarg

-- xxx going to put this here for now, to get things working. going to
-- transition to proper config merging.

-- Default configuration; any of these may get replaced by a configuration file
-- optionally specified.
local default = {
	abi_intptr_t = "intptr_t",
	abi_size_t = "size_t",
	abi_u_long = "u_long",
	abi_long = "long",
	abi_semid_t = "semid_t",
	abi_ptr_array_t = "",
	ptr_intptr_t_cast = "intptr_t",
    -- NOTE: putting these here temporarily, in case they're needed
    abi_flags_mask = 0,
    abi_flags = "",
}

local function check_abi_changes(arg)
	for k, v in pairs(config.known_abi_flags) do
		local exprs = v.exprs
		if config.abi_changes(k) and exprs ~= nil then
			for _, e in pairs(exprs) do
				if arg:find(e) then
					return true
				end
			end
		end
	end

	return false
end

local function strip_arg_annotations(arg)
	arg = arg:gsub("_Contains_[^ ]*[_)] ?", "")
	arg = arg:gsub("_In[^ ]*[_)] ?", "")
	arg = arg:gsub("_Out[^ ]*[_)] ?", "")
	return util.trim(arg)
end

function scarg:init()
    self.local_abi_change = check_abi_changes(self.scarg)
	self.global_abi_change = self.global_abi_change or self.local_abi_change

    self.scarg = strip_arg_annotations(self.scarg)
    self.scarg = util.trim(self.scarg, ',')
    self.name = self.scarg:match("([^* ]+)$")
    self.type = util.trim(self.scarg:gsub(self.name .. "$", ""), nil) 
end

-- RETURN: TRUE, argument has type and needs to be added (is now processed).
--         FALSE, argument type is void, it doesn't need to be added.
function scarg:process()
    if self.type ~= "" and self.name ~= "void" then
		-- util.is64bittype() needs a bare type so check it after argname
		-- is removed
		self.global_abi_change = self.global_abi_change or 
                                 (config.abi_changes("pair_64bit") and 
                                 util.is64bittype(self.type))

		self.type = self.type:gsub("intptr_t", default.abi_intptr_t)
		self.type = self.type:gsub("semid_t", default.abi_semid_t)

		if util.isptrtype(self.type) then
			self.type = self.type:gsub("size_t", default.abi_size_t)
			self.type = self.type:gsub("^long", default.abi_long);
			self.type = self.type:gsub("^u_long", default.abi_u_long);
			self.type = self.type:gsub("^const u_long", "const " 
                    .. default.abi_u_long)
		elseif self.type:find("^long$") then
			self.type = default.abi_long
		end

		if util.isptrarraytype(self.type) and default.abi_ptr_array_t ~= "" then
			-- `* const *` -> `**`
            self.type = self.type:gsub("[*][ ]*const[ ]*[*]", "**")
			-- e.g., `struct aiocb **` -> `uint32_t *`
			self.type = self.type:gsub("[^*]*[*]", default.abi_ptr_array_t .. " ", 1)
		end

		-- XX TODO: Forward declarations? See: sysstubfwd in CheriBSD
		if self.local_abi_change then
			local abi_type_suffix = default.abi_type_suffix
			self.type = self.type:gsub("(struct [^ ]*)", "%1" ..
			    default.abi_type_suffix)
			self.type = self.type:gsub("(union [^ ]*)", "%1" ..
			    default.abi_type_suffix)
		end

        return true
    end

    -- xxx print status message
    return false
end

-- Pad if necessary, to keep index aligned (for pairing 64-bit arguments).
-- @return TRUE if padded, FALSE if not
function scarg:pad(tbl)
    if #tbl % 2 == 1 then
        table.insert(tbl, {
            type = "int",
            name = "_pad",
        })
        return true
    end

    return false
end

-- Append to the syscall's argument table.
-- @note Appends to the end. Order is the responsibility of the caller.
-- @return TRUE if appended, FALSE if not
function scarg:append(tbl)
    if config.abi_changes("pair_64bit") and util.is64bittype(self.type) then
        self:pad(tbl)
    	table.insert(tbl, {
    		type = "uint32_t",
    		name = self.name .. "1",
    	})
    	table.insert(tbl, {
    		type = "uint32_t",
    		name = self.name .. "2",
    	})
        return true
    else
    	table.insert(tbl, {
    		type = self.type,
    		name = self.name,
    	})
        return true
    end

    return false
end
        
function scarg:new(obj, line)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self
    
    self.scarg = line
    self.name = ""
    self.type = ""
    self.argtbl = {}

	self.local_abi_change = false
    self.global_abi_change = false -- xxx needs to be k, v in cfg table
    -- xxx could also leave this here and have it merge into cfg tbl as part of
    -- destructor. Make that work in lua.

    obj:init()

	return obj
end

return scarg
