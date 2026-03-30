# Doc Linking

Use `[doc NN](relative-path.md)` — never bare "doc NN". Relative paths from source file. Dimensions via `dimensions/NN-name.md`.

```
WRONG: "as described in doc 14"
RIGHT: "as described in [doc 14](../docs/reflections/14-architecture.md)"
RIGHT: "see [doc 22](dimensions/22-testing.md) for testing patterns"
```
