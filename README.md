# zigma-definition

system-definition all in zig

## Install

```sh
zig fetch --save git+https://github.com/ari-dc-uba-ar/zigma-definition.git#v0.1.0
```

Then, in your `build.zig`:

```zig
const zigma = b.dependency("zigma_definition", .{}).module("zigma");
exe.root_module.addImport("zigma", zigma);
```

The package also exports the module `aida`, the example system described in
`examples/aida.zig`.

Requires the Zig version declared as `minimum_zig_version` in `build.zig.zon`.

## License

MIT. See [LICENSE](LICENSE).
