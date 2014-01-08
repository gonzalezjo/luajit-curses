local console = {}
local curses = require("curses")
local ffi = require("ffi")

function print(...)
	for i = 1, select("#", ...) do
		local val = tostring(select(i, ...))
		io.write(val)
	end
	io.write("\n")
end

local function string_explode(self, sep, pattern)
	sep = sep or ""
	pattern = pattern or false
	
	if sep == "" then
		local tbl = {}
		local i = 1
		for char in self:gmatch(".") do
			tbl[i] = char
			i=i+1
		end
		return tbl
	end

	local tbl = {}
	local i, last_pos = 1,1
	local new_sep = sep

	if not pattern then
		new_sep = new_sep:gsub("[%-%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
	end

	for start_pos, end_pos in self:gmatch("()"..new_sep.."()") do
		tbl[i] = self:sub(last_pos, start_pos-1)
		last_pos = end_pos
		i=i+1
	end

	tbl[i] = self:sub(last_pos)
	
	return tbl
end

console.curses = console.curses or {}
local c = console.curses

c.line = c.line or ""
c.scroll = c.scroll or 0
c.current_table = c.current_table or G
c.table_scroll = c.table_scroll or 0
local history = {}

local translate = 
{
	[32] = "KEY_SPACE",
	[9] = "KEY_TAB",
	[10] = "KEY_ENTER",
	[459] = "KEY_ENTER",
	[8] = "KEY_BACKSPACE",
	[127] = "KEY_BACKSPACE",
	
	-- this is bad, fix me!!!
	[443] = "KEY_CTRL_LEFT",
	[444] = "KEY_CTRL_RIGHT",
	[527] = "KEY_CTRL_DELETE",
	[127] = "KEY_CTRL_BACKSPACE",
}

-- some helpers

local function gety()
	return curses.getcury(c.input_window)
end

local function getx()	
	return curses.getcurx(c.input_window)
end

local function move_cursor(x)
	curses.wmove(c.input_window, gety(), math.min(getx() + x, #c.line))
	curses.wrefresh(c.input_window)
end

local function set_cursor_pos(x)
	curses.wmove(c.input_window, 0, math.max(x, 0))
	curses.wrefresh(c.input_window)
end

function console.InsertChar(char)
	if #c.line == 0 then
		c.line = c.line .. char
	elseif subpos == #c.line then
		c.line = c.line .. char
	else
		c.line = c.line:sub(1, getx()) .. char .. c.line:sub(getx() + 1)
	end

	console.ClearInput(c.line)

	move_cursor(1)
end

function console.GetCurrentLine()
	return c.line
end
 
function console.InitializeCurses()
	if console.curses_init then return end
	
	--curses.freeconsole()

	c.parent_window = curses.initscr()

	if jit.os == "Windows" then
		curses.resize_term(25,130)
	end

	c.log_window = curses.derwin(c.parent_window, curses.LINES-1, curses.COLS, 0, 0)
	c.input_window = curses.derwin(c.parent_window, 1, curses.COLS, curses.LINES - 1, 0)
	
	curses.cbreak()
	curses.noecho()

	curses.nodelay(c.input_window, 1)
	curses.keypad(c.input_window, 1)

	curses.scrollok(c.log_window, 1)

	curses.attron((2 ^ (8 + 13)) + 8 * 256)

	do
		local function split_by_length(str, len)
			if #str > len then
				local tbl = {}
				
				local max = math.floor(#str/len)
				local leftover = #str - (max * len)
				
				for i = 0, max do
					
					local left = i * len
					local right = (i * len) + len
							
					table.insert(tbl, str:sub(left, right))
				end
				
				return tbl
			end
			
			return {str}
		end

		local max_length = 256
		local suppress = false
		
		function io.write(...)
			if suppress then return end
			local str = table.concat({...}, "")
			str = str:gsub("\r", "\\r")
			
			if jit.os == "Windows" and #str > max_length then
				for k,v in pairs(split_by_length(str, max_length)) do
					for line in v:gmatch("(.-)\n") do
						io.write(line)
					end
				end
				return
			end
				
			curses.wprintw(c.log_window, str)
			curses.wrefresh(c.log_window)
		end
	end
	
	console.curses_init = true
end

console.InitializeCurses()

function console.ClearInput(str)
	local y, x = gety(), getx()
	
	curses.wclear(c.input_window)
	
	if str then
		curses.waddstr(c.input_window, str)		
		curses.wmove(c.input_window, y, x)
	else
		curses.wmove(c.input_window, y, 0)
	end
	
	curses.wrefresh(c.input_window)
end

function console.ClearWindow()
	curses.wclear(c.log_window)
	curses.wrefresh(c.log_window)
end


function console.GetActiveKey()
	local byte = curses.wgetch(c.input_window)
	
	if byte < 0 then return end
		
	local key = translate[byte] or ffi.string(curses.keyname(byte))
	if not key:find("KEY_") then key = nil end
	
	return key
end

function console.HandleKey(key)
	--[[if key == "KEY_NPAGE" then
		curses.wscrl(c.parent_window, -5)
	elseif key == "KEY_PPAGE" then
		curses.wscrl(c.parent_window, 5)
	end]]
		
	if key == "KEY_UP" then
		c.scroll = c.scroll - 1
		c.line = history[c.scroll%#history+1] or c.line
		set_cursor_pos(#c.line)
	elseif key == "KEY_DOWN" then
		c.scroll = c.scroll + 1
		c.line = history[c.scroll%#history+1] or c.line
		set_cursor_pos(#c.line)
	end

	if key == "KEY_LEFT" then
		 move_cursor(-1)
	elseif key == "KEY_CTRL_LEFT" then
		set_cursor_pos((select(2, c.line:sub(1, getx()+1):find(".+[^%p%s]")) or 1) - 2)
	elseif key == "KEY_RIGHT" then
		 move_cursor(1)
	elseif key == "KEY_CTRL_RIGHT" then
		local pos = (select(2, c.line:find("[%s%p].-[^%p%s]", getx()+1)) or 1) - 1
		if pos < getx() then
			pos = #c.line
		end
		set_cursor_pos(pos)
	end

	if key == "KEY_HOME" then
		set_cursor_pos(0)
	elseif key == "KEY_END" then
		set_cursor_pos(#c.line)
	end

	-- space
	if key == "KEY_SPACE" then
		console.InsertChar(" ")
	end

	-- tab
	if key == "KEY_TAB" then
		local start, stop, last_word = c.line:find("([_%a%d]-)$")
		if last_word then
			local pattern = "^" .. last_word
							
			if (not c.line:find("%(") or not c.line:find("%)")) and not c.line:find("io%.write") then
				c.in_function = false
			end
							
			if not c.in_function then
				c.current_table = string_explode(c.line, ".")
										
				local tbl = _G
				
				for k,v in pairs(c.current_table) do
					if type(tbl[v]) == "table" then
						tbl = tbl[v]
					else
						break
					end
				end
				
				c.current_table = tbl or _G						
			end
			
			if c.in_function then
				local start = c.line:match("(.+%.)")
				if start then
					local tbl = {}
					
					for k,v in pairs(c.current_table) do
						table.insert(tbl, {k=k,v=v})
					end
					
					if #tbl > 0 then
						table.sort(tbl, function(a, b) return a.k > b.k end)
						c.table_scroll = c.table_scroll + 1
						
						local data = tbl[c.table_scroll%#tbl + 1]
						
						if type(data.v) == "function" then
							c.line = start .. data.k .. "()"
							set_cursor_pos(#c.line)
							move_cursor(-1)
							c.in_function = true
						else
							c.line = "io.write(" .. start .. data.k .. ")"
							set_cursor_pos(#c.line)
							move_cursor(-1)
						end
					end
				end
			else						
				for k,v in pairs(c.current_table) do
					k = tostring(k)
					
					if k:find(pattern) then
						c.line = c.line:sub(0, start-1) .. k
						if type(v) == "table" then 
							c.current_table = v 
							c.line = c.line .. "."
							set_cursor_pos(#c.line)
						elseif type(v) == "function" then
							c.line = c.line .. "()"
							set_cursor_pos(#c.line)
							move_cursor(-1)
							c.in_function = true
						else
							c.line = "io.write(" .. c.line .. ")"
						end
						break
					end
				end
			end
		end
	end

	-- backspace
	if key == "KEY_BACKSPACE" or (key == "KEY_CTRL_BACKSPACE" and jit.os == "Linux") then
		if getx() > 0 then
			local char = c.line:sub(1, getx())
			
			if char == "." then
				c.current_table = previous_table
			end
			
			c.line = c.line:sub(1, getx() - 1) .. c.line:sub(getx() + 1)
			move_cursor(-1)
		else
			console.ClearInput()
		end
	elseif key == "KEY_CTRL_BACKSPACE" then
		local pos = (select(2, c.line:sub(1, getx()):find(".*[%s%p].-[^%p%s]")) or 1) - 1
		c.line = c.line:sub(1, pos) .. c.line:sub(getx() + 1)
		set_cursor_pos(pos - 1)
	elseif key == "KEY_DC" then
		c.line = c.line:sub(1, getx()) .. c.line:sub(getx() + 2)			
	elseif key == "KEY_CTRL_DELETE" then
		local pos = (select(2, c.line:find("[%s%p].-[^%p%s]", getx()+1)) or #c.line + 1) - 1
		c.line = c.line:sub(1, getx()) .. c.line:sub(pos + 1)
	end
		
	-- enter
	if key == "KEY_ENTER" then
		console.ClearInput()

		if c.line ~= "" then			
			for key, str in pairs(history) do
				if str == c.line then
					table.remove(history, key)
				end
			end
			
			table.insert(history, c.line)

			c.scroll = 0
			console.ClearInput()
			
			io.write("> ", c.line, "\n")
			
			local res, err = pcall(loadstring(c.line))

			if not res then
				io.write(err, "\n")
			end
			
			c.current_table = _G
			c.in_function = false
			c.line = ""
		end
	end

	console.ClearInput(c.line)
end

function console.HandleChar(char)
	console.InsertChar(char)
end

while true do
	local byte = curses.wgetch(c.input_window)

	if byte > 0 then
			
		local key = translate[byte] or ffi.string(curses.keyname(byte))
		if not key:find("KEY_") then key = nil end
				
		if key then					
			key = ffi.string(key)
						
			console.HandleKey(key)
		elseif byte < 256 then
			local char = string.char(byte)
					
			console.HandleChar(char)
		end
	end
end