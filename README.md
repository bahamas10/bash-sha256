sha256 Implemented in Bash
=======================

Pure bash implementation of the sha256 checksum algorithm

Usage
----

```
./sha256 file.txt
./sha256 < file.bin
echo 'hello' | ./sha256
DEBUG=1 ./sha256 file.txt
SHA256_PROCS=1 ./sha256 file.txt
```

`DEBUG=1` traces every byte.  `SHA256_PROCS=1` runs in a single process instead
of the default two, which is faster below about 1 KiB of input.

How it works
----

bash charges for every command it dispatches and for every variable it touches
in an arithmetic expression, so what runs fast here is straight line arithmetic
with no loops, no arrays and no function calls in it.  That is too repetitive to
write out, so `build-core` and friends assemble it at startup and `eval` it into
place.  It works out about 7x faster than the loop it replaces.

- the 64 rounds are unrolled into one `(( ... ))`, and the eight working
  variables are rotated by renaming them each round rather than by copying
- the message schedule lives in 16 scalars updated in place, never an array
- values are stored as `v|v<<32`, so a 32-bit rotate is a single `>>n` read
  instead of a two-read `(v>>n|v<<32-n)`
- bytes are decoded through a lookup table rather than a `printf` each, and
  every read is re-sliced into 64-byte blocks first, because `${s:i:1}` is
  linear in the length of `s`
- decoding bytes never touches the hash state, so it runs in a second process
  and overlaps the strictly serial compression.  Records cross as fixed-width
  text read back with `read -N`, because bash reads a pipe one byte at a time
  in line mode but in bulk when it knows the count

Testing
----

```
./test-sha256           # known-answer vectors
tools/fuzz-sha256.sh    # 1217 inputs diffed against the system sha256sum
```

Which of the block, word, byte, bulk-NUL and padding paths runs depends on
where NUL bytes land, so the fuzzer walks every length and NUL placement that
changes the answer, plus all 256 byte values, across all four modes.

YouTube
-------

Watch me build this live on YouTube.

<a href="https://www.youtube.com/watch?v=GXibFvdKiO8"><img alt="Bash sha256 YouTube
Thumbnail" src="https://files.daveeddy.com/ysap/bash-sha256-thumbnail.jpg"
/></a>

License
-------

MIT License
