# il2cpp dumper

A proof-of-concept runtime dumper for il2cpp games.

## Features

Currently implemented features:
- C# definitions generation;

## Building the Project

Compile the DLL using:
```
zig build -Doptimize=ReleaseFast
```

Zig version: `0.16.0-dev.3121+d34b868bc`

## Usage

> [!NOTE]
> This is a proof-of-concept tool; it will only work with games that export all required il2cpp symbols.

To use the tool, you need to inject the generated DLL into the game process. Use [Proton Injector](https://github.com/jokelbaf/proton-injector) for Linux or [Pydll Injector](https://github.com/jokelbaf/pydll-injector) for Windows. 

Alternatively, you could replace an existing game DLL and re-export its symbols to load your dll without using an injector. See an example [here](https://github.com/jokelbaf/il2cpp-dumper/tree/akef).

When `GameAssembly` initializes, il2cpp-dumper will generate the C# definitions in the `cs` folder near the game executable.

## Credits

Il2cpp module implementation was inspired by [this project](https://git.xeondev.com/LR/C).

## License

The project is licensed under the GNU General Public License v3.0. See [LICENSE](./LICENSE) for details.
