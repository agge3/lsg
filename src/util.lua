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

local util = {}

-- No char provided, trims whitespace. Char provided, trims char.
function util.trim(s, char)
	if s == nil then
		return nil
	end
	if char == nil then
		char = "%s"
	end
	return s:gsub("^" .. char .. "+", ""):gsub(char .. "+$", "")
end

-- Returns a table (list) of strings.
function util.split(s, re)
	local t = { }

	for v in s:gmatch(re) do
		table.insert(t, v)
	end
	return t
end

-- Aborts with a message and does a clean exit procedure.
function util.abort(status, msg)
	assert(io.stderr:write(msg .. "\n"))
	-- cleanup
	os.exit(status)
end

--
-- Returns a set.
--
-- PARAM: t, a list
--
-- EXAMPLE: param: {"foo", "bar"}, return: {foo = true, bar = true}
--
function util.set(t)
	local s = { }
	for _,v in pairs(t) do s[v] = true end
	return s
end

--
-- Returns a set.
--
-- PARAM: str, a string
-- PARAM: re, the pattern to construct keys from
--
function util.setFromString(str, re)
	local s = { }

	for v in str:gmatch(re) do
		s[v] = true
	end
	return s
end

--
--  Iterator that traverses a table following the order of its keys.
--  An optional parameter f allows the specification of an alternative order. 
--
--  CREDIT: https://www.lua.org/pil/19.3.html
--  LICENSE: MIT
--
function util.pairsByKeys(t, f)
	local a = {}
	for n in pairs(t) do table.insert(a, n) end
	table.sort(a, f)
	local i = 0      -- iterator variable
	local iter = function ()   -- iterator function
		i = i + 1
		if a[i] == nil then return nil
		else return a[i], t[a[i]]
		end
	end
	return iter
end

--
-- Checks for pointer types: '*', caddr_t, intptr_t.
--
-- PARAM: type, the type to check
-- 
-- PARAM: abi, nil or optional ABI-specified intptr_t.
--
function util.isPtrType(type, abi)
    local default = "intptr_t" or abi
	return type:find("*") or type:find("caddr_t") or type:find(default)
end

function util.isPtrArrayType(type)
	return type:find("[*][*]") or type:find("[*][ ]*const[ ]*[*]")
end

-- Find types that are always 64-bits wide.
function util.is64bitType(type)
	return type:find("^dev_t[ ]*$") or type:find("^id_t[ ]*$") 
        or type:find("^off_t[ ]*$")
end

-- 
-- Strip the ABI function prefix if it exists (e.g., "freebsd32_").
--
-- RETURN: The original function name, or the function name with the ABI prefix
-- stripped
--
function util.stripAbiPrefix(funcname, abiprefix)
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

-- Returns the correct argsize. "0" unless there's arguments or NODEF flag.
function util.processArgsize(syscall)
    if syscall.arg_alias ~= nil then 
        if syscall.type.SYSMUX then
            return "0"
        elseif #syscall.args ~= 0 or syscall.type.NODEF then
            return "AS(" .. syscall.arg_alias .. ")"
        else
            return "0"
        end
    end

    return "0"
end

-- CREDIT: Lua Game Development Cookbook, Mario Kasuba
-- ipairs for a sparse array
function util.ipairs_sparse(t)
  -- tmpIndex will hold sorted indices, otherwise
  -- this iterator would be no different from pairs iterator
  local tmpIndex = {}
  local index, _ = next(t)
  while index do
    tmpIndex[#tmpIndex+1] = index
    index, _ = next(t, index)
  end
  -- sort table indices
  table.sort(tmpIndex)
  local j = 1

  return function()
    -- get index value
    local i = tmpIndex[j]
    j = j + 1
    if i then
      return i, t[i]
    end
  end
end

return util
