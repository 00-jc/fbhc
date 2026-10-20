# fbhc: Fibonacci hash compiler

Fibonacci-hash perfect hash generator for short keyword sets.

This is designed to use specially in compilers that target languages with short
keywords.

## What it does

1. Tokenizes the input file with SIMD whitespace detection, packing each keyword
   into a little-endian `u64`.
2. If the keys differ in enough bit positions, finds a minimal set of bits that
   still tells every key apart and emits `representative_bits_hash()`, which
   gathers those bits into a dense index, plus the matching `TABLE_REPR[]`.
3. Searches for a fibonacci hash constant that maps every key
   to a unique slot, and emits `TABLE_FIB[]` plus an inline `fib_hash()`.

The output is C/C++ source (C23/C++ `constexpr` aware) printed to stdout. It
gives you two independent perfect-hash options; use whichever suits you:

| Hash | Table | Notes |
| --- | --- | --- |
| `representative_bits_hash(u64)` | `TABLE_REPR[REPRESENTATIVE_TABLE_SIZE]` | Only emitted when the keys differ in enough bit positions. Pure shifts/masks, no multiply. The table is sparse (size is `2^bits`). |
| `fib_hash(u64)` | `TABLE_FIB[]` | Multiply by the found constant and shift. Table size is `2^hash_bits`. |

## Usage

```sh
./zig-out/bin/fbhc examples/keywords.txt
```

Output for `examples/keywords.txt`:

```c
#if (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L) || defined(__cplusplus)
# define FBHC_CONSTEXPR constexpr
#else
# define FBHC_CONSTEXPR
#endif
#ifdef __GNUC__
__attribute__((__always_inline__, const, __flatten__, __unused__))
#endif
#ifdef __cplusplus
constexpr
#endif
static inline uint64_t
representative_bits_hash(uint64_t input)
{
  static const FBHC_CONSTEXPR uint64_t REPRESENTATIVE_BITS = 0x4020803;
  uint64_t result = 0;

  result |= ((input >> 0) & 0x3) << 0;
  result |= ((input >> 11) & 0x1) << 2;
  result |= ((input >> 17) & 0x1) << 3;
  result |= ((input >> 26) & 0x1) << 4;
  return result;
}
static const FBHC_CONSTEXPR uint64_t REPRESENTATIVE_TABLE_SIZE = 32;
static const uint64_t TABLE_REPR[REPRESENTATIVE_TABLE_SIZE] = {
	[23 ] = 0x000000656C696877, // while
	[17 ] = 0x000000006F686365, // echo
	[14 ] = 0x00000074616F6C66, // float
	[1  ] = 0x0000000000006669, // if
	[2  ] = 0x00000065736C6166, // false
	[24 ] = 0x000074706D6F7270, // prompt
	[30 ] = 0x006E61656C6F6F62, // boolean
	[22 ] = 0x0000000064696F76, // void
	[18 ] = 0x00006E7275746572, // return
	[11 ] = 0x0000676E69727473, // string
	[5  ] = 0x0000000000746E69, // int
	[16 ] = 0x0000000065757274, // true
	[0  ] = 0x000000000074656C, // let
	[10 ] = 0x6E6F6974636E7566, // function
	[4  ] = 0x0000000000006F64, // do
};
static const uint64_t TABLE_FIB[] = {
	[2  ] = 0x000000656C696877, // while
	[7  ] = 0x000000006F686365, // echo
	[14 ] = 0x00000074616F6C66, // float
	[9  ] = 0x0000000000006669, // if
	[6  ] = 0x00000065736C6166, // false
	[11 ] = 0x000074706D6F7270, // prompt
	[12 ] = 0x006E61656C6F6F62, // boolean
	[0  ] = 0x0000000064696F76, // void
	[5  ] = 0x00006E7275746572, // return
	[3  ] = 0x0000676E69727473, // string
	[15 ] = 0x0000000000746E69, // int
	[10 ] = 0x0000000065757274, // true
	[8  ] = 0x000000000074656C, // let
	[4  ] = 0x6E6F6974636E7566, // function
	[1  ] = 0x0000000000006F64, // do
};
#ifdef __GNUC__
__attribute__((__always_inline__, const, __flatten__, __unused__))
#endif
#ifdef __cplusplus
constexpr
#endif
static inline uint64_t
fib_hash(uint64_t input)
#ifdef __cplusplus
noexcept
#endif
{
  return ((input * 0xf395ca4ef2d38abb) >> 60);
}
#undef FBHC_CONSTEXPR
```

Look up a keyword by packing it into a `u64` the same way (zero-padded,
little-endian), calling `fib_hash` (or `representative_bits_hash`), and comparing against `TABLE_FIB[slot]` (or `TABLE_REPR[slot]`). The comparison is needed to reject non-keywords that hash to an occupied slot.

## Errors

- `KeyTooLong`: a keyword is longer than 8 bytes.
- `IdenticalKeys`: the input contains duplicates.
