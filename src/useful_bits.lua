-- handle_noncompat
    if flags & known_flags.SYSMUX ~= 0 then
		argssize = "0"
	elseif #funcargs > 0 or flags & known_flags.NODEF ~= 0 then
		argssize = "AS(" .. argalias .. ")"
	else
		argssize = "0"
	end

-- what's in class syscall right now
s:compat_level() -- obsol, reserved, unimpl, freebsd compat, etc.
s:num
s:audit
s:name
s:altname
s:alttag
s:altrtyp
s:ret
s:args

-- need
num         [x]
thr_flag    [x]
flags       [x] -- needs work
sysflags    [x] -- can be handled, see below
rettype     [x]
auditev     [x]
ret         [x]
funcname    [x]
funcalias   [~]
funcargs    [x]
argalias    [~]

argalias & funcalias:
if alt ~= nil and alt ~= "" then
	local altExpr = "^([^%s]+)%s+([^%s]+)%s+([^%s]+)"
	funcalias, argalias, rettype = alt:match(altExpr)
	funcalias = trim(funcalias)
	if funcalias == nil or argalias == nil or rettype == nil then
		abort(1, "Malformed alt: " .. line)
	end
end

-- num check


if (flags & get_mask({"RESERVED", "UNIMPL"})) == 0 and sysnum == nil then
	abort(1, "Range only allowed with RESERVED and UNIMPL: " .. line)
end

-- NONCOMPAT:
local ncompatflags = get_mask({"STD", "NODEF", "NOARGS", "NOPROTO",
	    "NOSTD"})

-- args flagging changes_abi
local funcargs = {}
local changes_abi = false
if args ~= nil then
	funcargs, changes_abi = process_args(args)
end

sysflags = "0"
if flags & known_flags.CAPENABLED ~= 0 or
    config.capenabled[funcname] ~= nil or
    config.capenabled[stripped_name] ~= nil then
	sysflags = "SYF_CAPENABLED"
end

-- SYSCALL:CHECK_ABI()
if changes_abi then
	-- argalias should be:
	--   COMPAT_PREFIX + ABI Prefix + funcname
	argprefix = config.abi_func_prefix
	funcprefix = config.abi_func_prefix
	funcalias = funcprefix .. funcname
	noproto = false
end
if funcname ~= nil then
	funcname = funcprefix .. funcname
end
if funcalias == nil or funcalias == "" then
	funcalias = funcname
end

if argalias == nil and funcname ~= nil then
	argalias = funcname .. "_args"
	for _, v in pairs(compat_options) do
		local mask = v.mask
		if (flags & mask) ~= 0 then
			-- Multiple aliases doesn't seem to make
			-- sense.
			argalias = v.prefix .. argalias
			goto out
		end
	end
	::out::
elseif argalias ~= nil then
	argalias = argprefix .. argalias
end

-- Pointer arg?
if argtype:find("*") then
	desc = "userland " .. argtype
else
	desc = argtype;
end

local compat_set = config.compat_set
if compat_set ~= "" then
	if not compat_option_sets[compat_set] then
		abort(1, "Undefined compat set: " .. compat_set)
	end

	compat_options = compat_option_sets[compat_set]
else
	compat_options = {}
end

-- We ignore errors here if we're relying on the default configuration.
if not config_modified.capenabled then
	config.capenabled = grab_capenabled(config.capabilities_conf,
	    config_modified.capabilities_conf == nil)
elseif config.capenabled ~= "" then
	-- Due to limitations in the config format mostly, we'll have a comma
	-- separated list.  Parse it into lines
	local capenabled = {}
	-- print("here: " .. config.capenabled)
	for sysc in config.capenabled:gmatch("([^,]+)") do
		capenabled[sysc] = true
	end
	config.capenabled = capenabled
end
process_compat()
process_abi_flags()
process_syscall_abi_change()
process_obsol()
process_unimpl()
