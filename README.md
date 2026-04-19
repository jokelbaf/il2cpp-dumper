# il2cpp dumper

A proof-of-concept runtime dumper for il2cpp games.

> [!IMPORTANT]
> The branch demonstrates how to load the dumper into the game by replacing an existing DLL and re-exporting its symbols. **It will only work with Endfield.**

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

To use the tool, replace `gfsdk.dll` in game directory with the compiled DLL.

When `GameAssembly` initializes, il2cpp-dumper will generate the C# definitions in the `cs` folder near the game executable.

## Credits

Il2cpp module implementation was inspired by [this project](https://git.xeondev.com/LR/C).

## License

The project is licensed under the GNU General Public License v3.0. See [LICENSE](./LICENSE) for details.
