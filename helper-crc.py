import random
import sys
import zlib
from pathlib import Path

SLOT = 8


def solve(linear, target):
    basis = {}
    for j in range(32):
        v, e = linear(1 << j), 1 << j
        for lb in sorted(basis, reverse=True):
            if v >> lb & 1:
                bv, be = basis[lb]
                v ^= bv
                e ^= be
        if v:
            basis[v.bit_length() - 1] = (v, e)
    x = 0
    for lb in sorted(basis, reverse=True):
        if target >> lb & 1:
            bv, be = basis[lb]
            target ^= bv
            x ^= be
    if target:
        raise SystemExit("helper-crc: the CRC map is singular")
    return x


def forced(data, pos, want):
    before, after = bytes(data[:pos]), bytes(data[pos + 4 :])
    crc_before = zlib.crc32(before)
    after_zero = zlib.crc32(after, 0)
    mid = solve(lambda s: zlib.crc32(after, s) ^ after_zero, want ^ after_zero)
    zeros = b"\0" * 4
    zero_crc = zlib.crc32(zeros, 0)
    state = solve(lambda u: zlib.crc32(zeros, u) ^ zero_crc, mid ^ zero_crc)
    return (state ^ crc_before).to_bytes(4, "little")


def match(helper, pristine, marker):
    data = bytearray(Path(helper).read_bytes())
    want = zlib.crc32(Path(pristine).read_bytes())
    key = b"# " + marker.encode() + b" "
    pos = data.index(key) + len(key)
    printable = range(0x20, 0x7F)
    rng = random.Random(0)
    for _ in range(100000):
        data[pos : pos + 4] = bytes(rng.choice(printable) for _ in range(4))
        tail = forced(data, pos + 4, want)
        if all(b in printable for b in tail):
            data[pos + 4 : pos + SLOT] = tail
            if zlib.crc32(data) != want:
                raise SystemExit("helper-crc: the forced CRC does not match")
            Path(helper).write_bytes(data)
            return
    raise SystemExit("helper-crc: no printable slot found")


def verify(helper, pristine):
    a = Path(helper).read_bytes()
    b = Path(pristine).read_bytes()
    if len(a) != len(b) or zlib.crc32(a) != zlib.crc32(b):
        raise SystemExit(1)


if __name__ == "__main__":
    verb, args = sys.argv[1], sys.argv[2:]
    {"match": match, "verify": verify}[verb](*args)
