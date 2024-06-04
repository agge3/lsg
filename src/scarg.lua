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
	abi_func_prefix = "",
	abi_type_suffix = "",
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

-- xxx maybe is a util, keeping here for now because it felt very awkward in
-- util and doesn't really offer global value
local function strip_abi_prefix(funcname)
	local abiprefix = default.abi_func_prefix
	local stripped_name
	if funcname == nil then
		return nil
	end
	if abiprefix ~= "" and funcname:find("^" .. abiprefix) then
		stripped_name = funcname:gsub("^" .. abiprefix, "")
	else
		stripped_name = funcname
	end

	return stripped_name
end

-- Check both literal intptr_t and the abi version because this needs
-- to work both before and after the substitution
local function isptrtype(type)
	return type:find("*") or type:find("caddr_t") or
	    type:find("intptr_t") or type:find(default.abi_intptr_t)
end

local function isptrarraytype(type)
	return type:find("[*][*]") or type:find("[*][ ]*const[ ]*[*]")
end

-- Find types that are always 64-bits wide
local function is64bittype(type)
	return type:find("^dev_t[ ]*$") or type:find("^id_t[ ]*$") 
        or type:find("^off_t[ ]*$")
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
		-- is64bittype() needs a bare type so check it after argname
		-- is removed
		self.global_abi_change = self.global_abi_change or 
                                 (config.abi_changes("pair_64bit") and 
                                 is64bittype(self.type))

		self.type = self.type:gsub("intptr_t", default.abi_intptr_t)
		self.type = self.type:gsub("semid_t", default.abi_semid_t)

		if isptrtype(self.type) then
			self.type = self.type:gsub("size_t", default.abi_size_t)
			self.type = self.type:gsub("^long", default.abi_long);
			self.type = self.type:gsub("^u_long", default.abi_u_long);
			self.type = self.type:gsub("^const u_long", "const " 
                    .. default.abi_u_long)
		elseif self.type:find("^long$") then
			self.type = default.abi_long
		end

		if isptrarraytype(self.type) and default.abi_ptr_array_t ~= "" then
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

function scarg:add()
    if config.abi_changes("pair_64bit") and is64bittype(self.type) then
        -- xxx will need to figure out how to handle this padding, since we don't
        -- see the global table
    	--if #self.funcargs % 2 == 1 then
    	--	self.funcargs[#self.funcargs + 1] = {
    	--		type = "int",
    	--		name = "_pad",
    	--	}
    	--end


        -- since we're creating a new table with each scarg obj, it's OK to assume
        -- idx at 1
    	self.argtble[1] = {
    		type = "uint32_t",
    		name = self.name .. "1",
    	}
    	self.argtbl[2] = {
    		type = "uint32_t",
    		name = self.name .. "2",
    	}
    else
    	self.argtbl[1] = {
    		type = self.type,
    		name = self.name,
    	}
    end

    return self.argtbl
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
