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

function util.processArgsize(syscall)
    if #syscall.args ~= 0 or syscall.type.NODEF then
        return "AS(" .. syscall.arg_alias .. ")"
    end

    return "0"
end

function util.cleanup()
	--for _, v in pairs(files) do
	--	assert(v:close())
	--end

	if config.cleantmp then
		if lfs.dir(config.tmpspace) then
			for fname in lfs.dir(tmpspace) do
				if fname ~= "." and fname ~= ".." then
					assert(os.remove(config.tmpspace .. "/" ..
					    fname))
				end
			end
		end

		if lfs.attributes(config.tmpspace) and not lfs.rmdir(config.tmpspace) then
			assert(io.stderr:write("Failed to clean up tmpdir: " ..
			    config.tmpspace .. "\n"))
		end
	else
		assert(io.stderr:write("Temp files left in " .. config.tmpspace ..
		    "\n"))
	end
end


-- CREDIT: http://lua-users.org/wiki/CopyTable
function util.shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- CREDIT: http://lua-users.org/wiki/CopyTable
function util.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[util.deepcopy(orig_key)] = util.deepcopy(orig_value)
        end
        setmetatable(copy, util.deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- CREDIT: http://lua-users.org/wiki/CopyTable
-- Save copied tables in `copies`, indexed by original table.
function util.deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[util.deepcopy(orig_key, copies)] = util.deepcopy(orig_value, copies)
            end
            setmetatable(copy, util.deepcopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

return util
