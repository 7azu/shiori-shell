--- @sync entry
-- "q": on quitting no "cd" comes anymore, without this only the inactivity lock would apply.
-- Own sync plugin: a running async plugin counts as a task, and yazi then asks "Quit anyway?".
-- That is why the unmount runs detached and tries several times: yazi holds the folder until it has really quit;
-- the actual quitting is done by the "quit" after it in keymap.toml.

-- Same rule as plugins/vault.yazi: folder "X" with ".x" (or ".X") next to it that contains gocryptfs.conf
local function vault_of(path)
	local dir = path:gsub("/+$", "")
	while dir ~= "" do
		local parent, name = dir:match("^(.*)/([^/]+)$")
		if not parent then
			return nil
		end
		if name:sub(1, 1) ~= "." then
			for _, candidate in ipairs { "." .. name:lower(), "." .. name } do
				local f = io.open(parent .. "/" .. candidate .. "/gocryptfs.conf", "r")
				if f then
					f:close()
					return dir
				end
			end
		end
		dir = parent
	end
	return nil
end

return {
	entry = function()
		local done = {}
		for i = 1, #cx.tabs do
			local mount = vault_of((tostring(cx.tabs[i].current.cwd):gsub("^search://[^/]*/", "")))
			if mount and not done[mount] then
				done[mount] = true
				-- "cd /": otherwise the shell inherits yazi's working directory in the vault and blocks the unmount itself
				local quoted = "'" .. mount:gsub("'", "'\\''") .. "'"
				os.execute("setsid -f sh -c 'cd /; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do sleep 1; mountpoint -q \"$1\" || exit; fusermount3 -u \"$1\" && exit; done' _ " .. quoted .. " >/dev/null 2>&1")
			end
		end
	end,
}
