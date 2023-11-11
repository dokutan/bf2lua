#!/usr/bin/env lua

--- Brainfuck shell
-- @script bfsh

local bf_utils = require("bf_utils")
local has_readline, RL = pcall(function() return require("readline") end)

-- readline fallback
if not has_readline then
    print("Install the readline module for a better experience.")
    RL = {}
    RL.readline = function(prompt)
        io.write(prompt)
        return io.read()
    end
    RL.add_history = function(_) end
    RL.set_readline_name = function(_) end
    RL.set_complete_list = function(_) end
end

--- unescape `str`
local unescape = function(str)
    return str:gsub("\\n", "\n"):gsub("\\0", "\0"):gsub("\\\\", "\\")
end

local help_message = [[
bfsh.lua - brainfuck shell

Options:
-h --help         print this message
-i --input FILE   input file, - for stdin
-f --functions    create a function for each loop
                  this improves compatibility with luajit and lua<5.4
]]


--- Colors
local colors = {
    reset = "\x1b[0m",
    red = "\x1b[91m",
    yellow = "\x1b[93m",
    magenta = "\x1b[95m",
}

--- Brainfuck state
data = {}
ptr = 1
max = 256
setmetatable(data, {__index = function() return 0 end})
printlua = false
trace = nil
input = nil

--- Shell commands
commands = {}
setmetatable(commands, {__index = function() return function() print(colors.red .. "unknown command" .. colors.reset) end end})

function commands.ptr(arg)
    if arg:match("%d+") then
        ptr = tonumber(arg)
    else
        print(ptr)
    end
end

function commands.reset(_)
    data = {}
    setmetatable(data, {__index = function() return 0 end})
    ptr = 1
    trace = nil
end

function commands.echo(arg)
    print(colors.yellow .. unescape(arg) .. colors.reset)
end

function commands.get(_)
    print(data[ptr], ((data[ptr] >= 32 and data[ptr] <= 126) and string.char(data[ptr]) or ""))
end

function commands.getdouble(_)
    print(data[ptr] + data[ptr+3] * 256)
end

function commands.getstring(arg)
    for i=0,tonumber(arg) do
        io.write("\\" .. data[ptr+i])
        -- if data[ptr+i] == 10 then
        --     io.write("\\n")
        -- elseif data[ptr+i] < 32 or data[ptr+i] > 126 then
        --     io.write("\\" .. data[ptr+i])
        -- else
        --     io.write(string.char(data[ptr+i]))
        -- end
    end
    print()
end

function commands.set(arg)
    data[ptr] = tonumber(arg) % max
end

function commands.inc(arg)
    data[ptr] = data[ptr] + tonumber(arg) % max
end

function commands.dec(arg)
    data[ptr] = data[ptr] - tonumber(arg) % max
end

function commands.data(_)
    io.write(ptr .. ": ")
    for i = -8, 8 do
        if i == 0 then io.write("[") end
        io.write(string.format("%03d", data[ptr+i] or 0))
        if i == 0 then io.write("]") end
        io.write(" ")
    end
    io.write("\n")
end

function commands.trace(arg)
    if arg == "on" then
        trace = {}
    elseif arg == "off" then
        if not trace then
            print(colors.red .. "no trace started" .. colors.reset)
        else
            for _, p in ipairs(trace) do
                print(p)
            end
            trace = nil
        end
    end
end

function commands.printlua(arg)
    if arg == "on" then
        printlua = true
    elseif arg == "off" then
        printlua = false
    end
end

function commands.input(arg)
    if arg == "" then
        input = nil
    else
        input = unescape(arg)
    end
end

function commands.help(_)
    print([[Enter brainfuck code or a command, available commands:

help             show this message
ptr [VALUE]      set pointer to value, print pointer if VALUE is empty
reset            reset the brainfuck state
get              print value of the current cell
getdouble        print value of the current doubled cell (>low,0,0,high)
set VALUE        set current cell to VALUE
inc VALUE        increment current cell by VALUE
dec VALUE        decrement current cell by VALUE
data             print memory around the pointer
printlua on|off  print lua code
trace on|off     trace pointer movement
echo [TEXT]      print TEXT
input [TEXT]     use TEXT as brainfuck input, use stdin if TEXT is empty
]])
end

local run = function(command, prompt, functions, optimization, debugging, maximum)
    -- split command into lines
    local command_lines = {}
    command = command .. "\n"
    for line in command:gmatch("[^\n]*\n") do
        line = line:gsub("\n", "")

        table.insert(command_lines, line)
    end

    -- filter brainfuck lines (needed to count the loops)
    local bf_command_lines = {}
    for _, line in ipairs(command_lines) do
        if not line:match("^%s*[a-zA-Z]") then
            table.insert(bf_command_lines, line)
        end
    end

    -- count loops in brainfuck, read more lines if unmatched [
    local loops = bf_utils.count_brainfuck_loops(table.concat(bf_command_lines))
    while loops > 0 do
        local line = RL.readline(loops .. prompt)

        -- add line to command
        command = command .. line .. "\n"
        table.insert(command_lines, line)
        if not line:match("^%s*[a-zA-Z]") then
            table.insert(bf_command_lines, line)
        end

        loops = bf_utils.count_brainfuck_loops(table.concat(bf_command_lines))
    end

    if loops < 0 then
        print(colors.red .. "unmatched ]" .. colors.reset)
        return
    end

    -- add command to history
    RL.add_history(command:gsub("\n$", ""))

    -- convert lines to lua
    local lua_lines = {}
    for _, line in ipairs(command_lines) do
        if line:match("^%s*//") then
            -- comment
        elseif not line:match("^%s*[a-zA-Z]") then
            -- convert brainfuck to Lua
            local bf_code = bf_utils.optimize_brainfuck(line, optimization, debugging)
            local ir = bf_utils.convert_brainfuck(bf_code)
            local lua_code = bf_utils.convert_ir(ir, functions, debugging, maximum, "", "")

            -- modify Lua code
            if trace then
                lua_code = "trace[#trace + 1] = ptr\n" .. lua_code
                lua_code = lua_code:gsub("(ptr = [^\n]*)", "%1; trace[#trace + 1] = ptr")
            end
            if input then
                lua_code = lua_code:gsub("(string.byte%(io.read%(%d*%)%))", "string.byte(input) or 0; input = input:sub(2)")
            end

            table.insert(lua_lines, lua_code)
        else
            -- shell command
            local command_name, command_arg = line:gmatch("%s*([a-zA-Z]+)(.*)")()
            command_arg = command_arg:gsub("^%s*", ""):gsub("%s*$", ""):gsub("\\", "\\\\"):gsub('"', '\\"')
            local lua_code = "commands." .. command_name .. '("' .. command_arg .. '")'
            table.insert(lua_lines, lua_code)
        end
    end

    -- run Lua code
    local lua_code = table.concat(lua_lines, "\n")
    if printlua then print(colors.yellow .. lua_code .. colors.reset) end
    local bf_fn, message = load(lua_code)
    if bf_fn then
        --io.write(colors.magenta)
        bf_fn()
        --io.write(colors.reset)
        io.flush()
    else
        print(colors.red .. "failed to load lua code\n" .. message .. colors.reset)
    end

end

--- Main function.
local main = function()
    local functions = false -- use functions in the output ?
    local optimization = 0  -- optimization level
    local debugging = false -- enable debugging
    local maximum = 255     -- maximum value of a cell
    local infile = nil
    local default_prompt = "> "

    -- parse commandline args
    local i = 1
    while i <= #arg do
        if arg[i] == "-h" or arg[i] == "--help" then
            print(help_message)
            os.exit(0)
        elseif arg[i] == "-i" or arg[i] == "--input" then
            if arg[i + 1] == nil then
                print(colors.red .. "Option " .. arg[i] .. " requires an argument" .. colors.reset)
                os.exit(1)
            else
                infile = tostring(arg[i + 1])
                i = i + 1
            end
        elseif arg[i] == "-f" or arg[i] == "--functions" then
            functions = true
        else
            print(colors.red .. "Unknown option " .. arg[i] .. colors.reset)
            os.exit(1)
        end
        i = i + 1
    end

    if not infile then
        print("\x1b[1;96mbfsh - brainfuck shell")
        print("Enter `help` for a list of commands\x1b[0m")
    else
        local f, message = io.open(infile)
        if not f then
            print(colors.red .. "Failed to open " .. infile .. ": " .. message .. colors.reset)
            os.exit(1)
        end
        RL.readline = function(_)
            return f:read()
        end
    end

    -- command completion
    local completions = {}
    for name, _ in pairs(commands) do
        table.insert(completions, name)
    end
    RL.set_complete_list(completions)

    -- REPL
    local command = ""
    local prompt = default_prompt
    RL.set_readline_name("bfsh")
    while true do
        command = RL.readline(prompt)

        if command == nil then
            break -- EOF
        elseif command:match("^%s*//") then
            -- comment, do nothing
        else
            run(command, prompt, functions, optimization, debugging, maximum)
        end
    end
end

main()
