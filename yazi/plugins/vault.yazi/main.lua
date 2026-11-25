-- Encrypted folders (gocryptfs). A vault is a folder "X" with a hidden ciphertext folder ".x" (or ".X")
-- next to it that contains gocryptfs.conf. Same rule as the shell's folder browser
-- (quickshell/scripts/media_browse.py). Set one up with:  mkdir ~/Vault ~/.vault && gocryptfs -init ~/.vault
-- Without such a folder this plugin does nothing.
-- Hooks into the "cd" event instead of Enter/l: this way a mouse click or "g Space" also asks for the password,
-- and every way out of the folder locks it again.

-- gocryptfs locks itself after this much inactivity (not while a file is open)
local IDLE = "3m"
-- exit code of gocryptfs for a wrong password
local WRONG_PASSWORD = 12
-- Wait time before locking: re-entering after unlocking leaves the folder briefly, that must not lock
local LEAVE_DELAY = 0.3
-- While a file is open, the unmount fails: retry this often
local RETRY_SECONDS = 5

local function notify(content, level)
	ya.notify { title = "Vault", content = content, timeout = 5, level = level or "info" }
end

-- Plain path of a yazi URL: search results (fd/rg) have their own URL "search://<term>//path"
local function plain(url)
	return (tostring(url):gsub("^search://[^/]*/", ""))
end

local function parent_of(path)
	return path:match("^(.*)/[^/]+$") or "/"
end

local function is_file(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

-- Vault containing path (the folder itself or one above it): mount folder and ciphertext folder, or nil
local function vault_of(path)
	local dir = path:gsub("/+$", "")
	while dir ~= "" do
		local parent, name = dir:match("^(.*)/([^/]+)$")
		if not parent then
			return nil
		end
		if name:sub(1, 1) ~= "." then
			for _, candidate in ipairs { "." .. name:lower(), "." .. name } do
				local cipher = parent .. "/" .. candidate
				if is_file(cipher .. "/gocryptfs.conf") then
					return dir, cipher
				end
			end
		end
		dir = parent
	end
	return nil
end

-- ya.sync blocks see no upvalues, so the path checks are written out in each of them
local cwd_in = ya.sync(function(_, mount)
	local p = tostring(cx.active.current.cwd):gsub("^search://[^/]*/", "")
	return p == mount or p:sub(1, #mount + 1) == mount .. "/"
end)

local any_tab_in = ya.sync(function(_, mount)
	for i = 1, #cx.tabs do
		local p = tostring(cx.tabs[i].current.cwd):gsub("^search://[^/]*/", "")
		if p == mount or p:sub(1, #mount + 1) == mount .. "/" then
			return true
		end
	end
	return false
end)

local cwd_string = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

-- Vaults this plugin unlocked: Ctrl+L outside of any vault locks these
local remember = ya.sync(function(state, mount)
	state.opened = state.opened or {}
	state.opened[mount] = true
end)

local forget = ya.sync(function(state, mount)
	if state.opened then
		state.opened[mount] = nil
	end
end)

local opened = ya.sync(function(state)
	local list = {}
	for mount in pairs(state.opened or {}) do
		list[#list + 1] = mount
	end
	return list
end)

local function is_mounted(mount)
	local status = Command("mountpoint"):arg({ "-q", mount }):status()
	return status ~= nil and status.success
end

-- Password only via stdin: on the command line it would be visible to everyone in the process list
local function mount_vault(cipher, mount, password)
	local child, err = Command("gocryptfs")
		:arg({ "-q", "-idle", IDLE, "--", cipher, mount })
		:stdin(Command.PIPED)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()
	if not child then
		return nil, "gocryptfs cannot be started: " .. tostring(err)
	end
	child:write_all(password .. "\n")
	child:flush()
	local output = child:wait_with_output()
	if not output then
		return nil, "gocryptfs exited unexpectedly"
	end
	return output.status.code, output.stderr
end

local function unlock(mount, cipher)
	-- Locking briefly visits the folder to clear the display: do not open a prompt for that
	ya.sleep(0.15)
	if not cwd_in(mount) or is_mounted(mount) then
		return
	end

	local back = parent_of(mount)
	local title = "Vault password:"
	for _ = 1, 3 do
		local password, event = ya.input({ pos = { "center", w = 44 }, title = title, obscure = true })
		if event ~= 1 then
			ya.emit("cd", { back })
			return
		end
		local code, detail = mount_vault(cipher, mount, password or "")
		if code == 0 then
			remember(mount)
			-- Yazi already knows the folder as empty; a mount triggers no file event -> enter it again
			ya.emit("cd", { back })
			ya.emit("cd", { mount })
			return
		elseif code ~= WRONG_PASSWORD then
			notify("Unlocking failed: " .. tostring(detail), "error")
			ya.emit("cd", { back })
			return
		end
		title = "Wrong password, try again:"
	end
	notify("Wrong password three times", "error")
	ya.emit("cd", { back })
end

-- Deliberately no "-z": the data would stay readable for open programs, although it looks locked
local function unmount(mount)
	local output = Command("fusermount3"):arg({ "-u", mount }):output()
	return output ~= nil and output.status.success
end

-- Yazi does not notice the unmount and would otherwise keep showing the file names in the preview column
local function refresh_view(mount, back)
	ya.emit("cd", { mount })
	ya.sleep(0.05)
	ya.emit("cd", { back })
end

local function lock(mount)
	if not is_mounted(mount) then
		forget(mount)
		return
	end
	local back = cwd_string()
	if cwd_in(mount) then
		back = parent_of(mount)
		ya.emit("cd", { back })
		ya.sleep(0.2)
	end
	if unmount(mount) then
		forget(mount)
		refresh_view(mount, back)
		notify("Vault locked")
	else
		notify("Not locked, a file is still open (mpv, editor?)", "warn")
	end
end

-- Ctrl+L: the vault you are in, otherwise every vault this plugin unlocked. Nothing open -> nothing happens.
local function lock_command()
	local here = vault_of(plain(cwd_string()))
	if here then
		lock(here)
		return
	end
	for _, mount in ipairs(opened()) do
		lock(mount)
	end
end

-- Folder left: lock as soon as nothing speaks against it. Returning cancels the wait.
local function lock_after_leaving(mount)
	ya.sleep(LEAVE_DELAY)
	local warned = false
	while is_mounted(mount) and not any_tab_in(mount) do
		if unmount(mount) then
			forget(mount)
			refresh_view(mount, cwd_string())
			notify("Vault locked")
			return
		end
		if not warned then
			warned = true
			notify("Not locked yet, a file is open. Will retry.", "warn")
		end
		ya.sleep(RETRY_SECONDS)
	end
end

return {
	setup = function()
		-- Across all tabs: a change in another tab must not lock the vault away under this one
		local was_inside = {}
		ps.sub("cd", function()
			local inside = {}
			for i = 1, #cx.tabs do
				local mount = vault_of(plain(cx.tabs[i].current.cwd))
				if mount then
					inside[mount] = true
				end
			end
			local mount, cipher = vault_of(plain(cx.active.current.cwd))
			if mount then
				ya.emit("plugin", { "vault", "unlock " .. ya.quote(mount) .. " " .. ya.quote(cipher) })
			end
			for left in pairs(was_inside) do
				if not inside[left] then
					ya.emit("plugin", { "vault", "left " .. ya.quote(left) })
				end
			end
			was_inside = inside
		end)
	end,
	entry = function(_, job)
		local action = job.args[1]
		if action == "lock" then
			lock_command()
		elseif action == "left" then
			lock_after_leaving(job.args[2])
		elseif action == "unlock" then
			unlock(job.args[2], job.args[3])
		end
	end,
}
