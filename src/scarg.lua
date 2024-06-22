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

-- xxx we're not using flags anymore -- address
local function checkAbiChanges(arg)
	for k, v in pairs(config.known_abi_flags) do
		local exprs = v.exprs
		if config.abiChanges(k) and exprs ~= nil then
			for _, e in pairs(exprs) do
				if arg:find(e) then
					return true
				end
			end
		end
	end

	return false
end

-- Strips the Microsoft(R) SAL annotations from the argument(s).
local function stripArgAnnotations(arg)
	arg = arg:gsub("_Contains_[^ ]*[_)] ?", "")
	arg = arg:gsub("_In[^ ]*[_)] ?", "")
	arg = arg:gsub("_Out[^ ]*[_)] ?", "")
	return util.trim(arg)
end

-- Everytime a scarg object is created, it would go through this default 
-- initialization procedure, to prepare to handle the current parsing line's 
-- argument.
function scarg:init()
    self.local_abi_change = checkAbiChanges(self.scarg)
	self.global_abi_change = self.global_abi_change or self.local_abi_change

    self.scarg = stripArgAnnotations(self.scarg)
    self.scarg = util.trim(self.scarg, ',')
    self.name = self.scarg:match("([^* ]+)$")
    self.type = util.trim(self.scarg:gsub(self.name .. "$", ""), nil) 
end

--
-- Processes the argument, doing things such as: flagging for a global config
-- ABI change, converting to the default ABI, converting to the specified ABI,
-- handling 64-bit pairing, etc.
--
-- RETURN: TRUE, argument has type and needs to be added (is now processed)
--         FALSE, argument type is void, it doesn't need to be added
--
function scarg:process()
    -- Much of this is identical to makesyscalls.lua
    -- Notable changes are: using "self" for OOP, changes_abi is now 
    -- global_abi_change, arg_abi_change is now local_abi_change
    if self.type ~= "" and self.name ~= "void" then
		-- util.is64bittype() needs a bare type so check it after argname
		-- is removed
		self.global_abi_change = self.global_abi_change or 
                                 (config.abiChanges("pair_64bit") and 
                                 util.is64bittype(self.type))

		self.type = self.type:gsub("intptr_t", default.abi_intptr_t)
		self.type = self.type:gsub("semid_t", default.abi_semid_t)

		if util.isPtrType(self.type) then
			self.type = self.type:gsub("size_t", default.abi_size_t)
			self.type = self.type:gsub("^long", default.abi_long);
			self.type = self.type:gsub("^u_long", default.abi_u_long);
			self.type = self.type:gsub("^const u_long", "const " 
                    .. default.abi_u_long)
		elseif self.type:find("^long$") then
			self.type = default.abi_long
		end

		if util.isPtrArrayType(self.type) and default.abi_ptr_array_t ~= "" then
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

--
-- Pad if necessary, to keep index aligned (for pairing 64-bit arguments).
-- RETURN: TRUE if padded, FALSE if not
--
function scarg:pad(tbl)
    -- This is done all in one-go in makesyscalls.lua, but it's now it's own 
    -- procedure.
    if #tbl % 2 == 1 then
        table.insert(tbl, {
            type = "int",
            name = "_pad",
        })
        return true
    end

    return false
end

--
-- Append to the system call's argument table.
-- NOTE: Appends to the end, "order" is the responsibility of the caller.
-- RETURN: TRUE if appended, FALSE if not
--
function scarg:append(tbl)
    if config.abiChanges("pair_64bit") and util.is64bitType(self.type) then
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
        
-- Default constructor. scarg HAS a finalizer procedure so MAKE SURE to nil the
-- reference.
function scarg:new(obj, line)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self
    
    self.scarg = line
	self.local_abi_change = false
    self.global_abi_change = false

    obj:init()
        
    -- Setup lua "destructor", to merge the global ABI change flag into the 
    -- global config table. We've made sure to the nil the reference so this 
    -- should be a consistent guarantee.
    local proxy = setmetatable({ }, {
        __gc = function()
            obj:finalizer()
        end
    })
    obj.__gcproxy = proxy

	return obj
end

-- xxx this is not going to work right now, manage the global config table and 
-- then it will 
function scarg:finalizer()
    if self.global_abi_change then
        config.changes_abi = true;
    end
end

return scarg
