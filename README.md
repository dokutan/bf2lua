# bf2lua
Brainfuck to Lua transpiler

## Usage
- Clone this repository
- Make sure that you have Lua installed

Convert ``input.bf`` to ``output.lua``:
```
lua bf2lua -i input.bf -o output.lua
```

Convert and run ``input.bf``:
```
lua bf2lua -i input.bf
```

If you are using luajit or Lua < 5.4, the ``-f`` option can improve compatibility:
```
lua bf2lua -f -i input.bf
```

Set the optimization level (0-2, default is 1) with the ``-O`` option:
```
lua bf2lua -O 2 -i input.bf
```

## Optimisations and checks
- Useless combinations of Brainfuck commands like ``+-``, ``[]``, ``<>`` or ``+[]-`` are ignored
- Successive identical commands are combined into a single line of Lua code
- Simple loops (e.g. setting a cell to zero, addition) are replaced
- The total number of loop commands (``[`` and ``]``) is checked to be balanced


## Documentation
Documentation can be generated with ldoc:
```
ldoc bf2.lua -a -f markdown
```
