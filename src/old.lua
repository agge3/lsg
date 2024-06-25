local function gen_syscalls_h(tbl, config)
	local s = tbl.syscalls
	local m = 0

	for k, v in pairs(s) do
		if  v.type["STD"] ~= nil or
			v.type["NOSTD"] ~= nil
		then
			print(string.format("#define SYS_%s %d", v.name, v.num))
			if tonumber(v.num) > m then
				m = tonumber(v.num)
			end
		end
	end
	print(string.format("#define SYS_MAXSYSCALL %d", m + 1))
end
