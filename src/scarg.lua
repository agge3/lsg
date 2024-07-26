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

-- Check argument against config for ABI changes from native. Return TRUE if
-- there are.
local function checkAbiChanges(arg)
	for k, v in pairs(config.known_abi_flags) do
		if config.abiChanges(k) and v ~= nil then
			for _, e in pairs(v) do
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
    self.abi_changes = checkAbiChanges(self.scarg)
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
    -- Notable changes are: using `self` for OOP, arg_abi_change is now (local)
    -- abi_changes, and abi_changes is now global_changes_abi. There's also a
    -- helper function mergeGlobal() to merge changes into the global config.
    if self.type ~= "" and self.name ~= "void" then
		-- util.is64bitType() needs a bare type so check it after argname
		-- is removed
		self.global_changes_abi = config.abiChanges("pair_64bit") and 
                                  util.is64bitType(self.type)

		self.type = self.type:gsub("intptr_t", config.abi_intptr_t)
		self.type = self.type:gsub("semid_t", config.abi_semid_t)

		if util.isPtrType(self.type) then
			self.type = self.type:gsub("size_t", config.abi_size_t)
			self.type = self.type:gsub("^long", config.abi_long)
			self.type = self.type:gsub("^u_long", config.abi_u_long)
			self.type = self.type:gsub("^const u_long", "const " 
                    .. config.abi_u_long)
		elseif self.type:find("^long$") then
			self.type = config.abi_long
		end

		if util.isPtrArrayType(self.type) and config.abi_ptr_array_t ~= "" then
			-- `* const *` -> `**`
            self.type = self.type:gsub("[*][ ]*const[ ]*[*]", "**")
			-- e.g., `struct aiocb **` -> `uint32_t *`
			self.type = self.type:gsub("[^*]*[*]", config.abi_ptr_array_t .. " ", 1)
		end

		-- XX TODO: Forward declarations? See: sysstubfwd in CheriBSD
		if self.abi_changes then
			local abi_type_suffix = config.abi_type_suffix
			self.type = self.type:gsub("(struct [^ ]*)", "%1" ..
			    config.abi_type_suffix)
			self.type = self.type:gsub("(union [^ ]*)", "%1" ..
			    config.abi_type_suffix)
		end

        -- Finally, merge any changes to the ABI into the global config.
        self:mergeGlobal()

        return true
    end

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
function scarg:insert()
    if config.abiChanges("pair_64bit") and util.is64bitType(self.type) then
        self:pad(tbl)
    	table.insert(self.arg, {
    		type = "uint32_t",
    		name = self.name .. "1",
    	})
    	table.insert(self.arg, {
    		type = "uint32_t",
    		name = self.name .. "2",
    	})
    else
    	table.insert(self.arg, {
    		type = self.type,
    		name = self.name,
    	})
        return self.arg
    end
    return self.arg
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

function scarg:getArg()
    return self.arg
end
        
-- Default constructor. scarg HAS a finalizer procedure so MAKE SURE to nil the
-- reference.
function scarg:new(obj, line)
	obj = obj or { }
	setmetatable(obj, self)
	self.__index = self
    
    self.scarg = line
	self.abi_changes = false
    self.global_abi_changes = false

    self.arg = {}

    obj:init()

	return obj
end

-- Merge any changes to the ABI (changes from native) into the global config.
function scarg:mergeGlobal()
    if self.global_changes_abi then
        -- xxx this is what we're intending to do here, right?
        config.changes_abi = self.global_changes_abi
    end
end

return scarg
