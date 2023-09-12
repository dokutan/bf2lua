# bf2lua
Brainfuck to Lua transpiler

There are two programs in this repository:
- `bf2lua.lua`: Converts brainfuck to Lua, either running or outputing the result. Supports optimisations but has only minimal debugging support.
- `bfsh.lua`: A brainfuck shell, with special commands for development and debugging purposes.

## Dependencies
- Lua
- optional: the `readline` module, adds completion support and better line editing to `bfsh.lua`

## bf2lua.lua
Convert ``input.bf`` to ``output.lua``:
```sh
lua bf2lua.lua -i input.bf -o output.lua
```

Convert and run ``input.bf``:
```sh
lua bf2lua.lua -i input.bf
```

If you are using luajit or Lua < 5.4, the ``-f`` option can improve compatibility:
```sh
lua bf2lua.lua -f -i input.bf
```

Set the optimization level (0-2, default is 1) with the ``-O`` option:
```sh
lua bf2lua.lua -O 2 -i input.bf
```

### Optimisations and checks
- Useless combinations of Brainfuck commands like ``+-``, ``[]``, ``<>`` or ``+[]-`` are ignored
- Successive identical commands are combined into a single line of Lua code
- Simple loops (e.g. setting a cell to zero, addition) are replaced
- The total number of loop commands (``[`` and ``]``) is checked to be balanced

## bfsh.lua
Start the interactive shell:
```sh
lua bfsh.lua
```

Run `file.bf`:
```sh
lua bfsh.lua -i file.bf
```

`bfsh.lua` accepts additional commands, run the `help` command to get a full list. Brainfuck code, commands and comments can not be mixed in a single line. 

Example:
```
++++[
    get
    -
]
echo loop completed
```

## Documentation
Documentation can be generated with ldoc:
```
ldoc bf2.lua -a -f markdown
```
