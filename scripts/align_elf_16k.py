#!/usr/bin/env python3
"""Rewrite ELF PT_LOAD p_align to 16 KiB and insert padding so
p_offset ≡ p_vaddr (mod 16384). Used for bundled rclone / fusermount
executables that Android still checks because they are named *.so."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

PAGE = 16384
PT_LOAD = 1


def _u16(data: bytearray, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0]


def _u32(data: bytearray, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0]


def _u64(data: bytearray, off: int) -> int:
    return struct.unpack_from("<Q", data, off)[0]


def align_needed(have: int, need: int) -> int:
    if have == need:
        return 0
    if need >= have:
        return need - have
    return PAGE - have + need


def loads_ok(data: bytearray) -> bool:
    if data[:4] != b"\x7fELF":
        return False
    is64 = data[4] == 2
    if is64:
        ph_off, ph_ent, ph_num = _u64(data, 32), _u16(data, 54), _u16(data, 56)
    else:
        ph_off, ph_ent, ph_num = _u32(data, 28), _u16(data, 42), _u16(data, 44)
    found = False
    for i in range(ph_num):
        off = ph_off + i * ph_ent
        if _u32(data, off) != PT_LOAD:
            continue
        found = True
        if is64:
            p_offset, p_vaddr, p_align = _u64(data, off + 8), _u64(data, off + 16), _u64(data, off + 48)
        else:
            p_offset, p_vaddr, p_align = _u32(data, off + 4), _u32(data, off + 8), _u32(data, off + 28)
        if p_align < PAGE or (p_offset % PAGE) != (p_vaddr % PAGE):
            return False
    return found


def align_elf(path: Path) -> str:
    data = bytearray(path.read_bytes())
    if data[:4] != b"\x7fELF":
        return "not-elf"
    if loads_ok(data):
        return "already"

    is64 = data[4] == 2
    if is64:
        e_phoff, e_phentsize, e_phnum = _u64(data, 32), _u16(data, 54), _u16(data, 56)
        e_shoff, e_shentsize, e_shnum = _u64(data, 40), _u16(data, 58), _u16(data, 60)
    else:
        e_phoff, e_phentsize, e_phnum = _u32(data, 28), _u16(data, 42), _u16(data, 44)
        e_shoff, e_shentsize, e_shnum = _u32(data, 32), _u16(data, 46), _u16(data, 48)

    loads: list[dict] = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if _u32(data, off) != PT_LOAD:
            continue
        if is64:
            p_offset, p_vaddr = _u64(data, off + 8), _u64(data, off + 16)
        else:
            p_offset, p_vaddr = _u32(data, off + 4), _u32(data, off + 8)
        loads.append({"hdr_off": off, "p_offset": p_offset, "p_vaddr": p_vaddr})
    if not loads:
        return "no-load"

    loads.sort(key=lambda item: item["p_offset"])
    patches: list[tuple[int, int, int]] = []
    shift = 0
    for item in loads:
        cur = item["p_offset"] + shift
        pad = align_needed(cur % PAGE, item["p_vaddr"] % PAGE)
        if pad:
            patches.append((item["p_offset"], pad, cur))
            shift += pad

    if patches:
        # Insert from the end so earlier positions stay valid.
        for orig_pos, pad, insert_pos in reversed(patches):
            data[insert_pos:insert_pos] = b"\x00" * pad

        def shifted(orig: int) -> int:
            extra = 0
            for pos, pad, _ in patches:
                if orig >= pos:
                    extra += pad
            return orig + extra

        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = _u32(data, off)
            if is64:
                struct.pack_into("<Q", data, off + 8, shifted(_u64(data, off + 8)))
                if p_type == PT_LOAD:
                    struct.pack_into("<Q", data, off + 48, PAGE)
            else:
                struct.pack_into("<I", data, off + 4, shifted(_u32(data, off + 4)))
                if p_type == PT_LOAD:
                    struct.pack_into("<I", data, off + 28, PAGE)

        new_shoff = shifted(e_shoff)
        if is64:
            struct.pack_into("<Q", data, 40, new_shoff)
        else:
            struct.pack_into("<I", data, 32, new_shoff)
        if e_shnum and new_shoff + e_shnum * e_shentsize <= len(data):
            for i in range(e_shnum):
                sh = new_shoff + i * e_shentsize
                if is64:
                    struct.pack_into("<Q", data, sh + 24, shifted(_u64(data, sh + 24)))
                else:
                    struct.pack_into("<I", data, sh + 16, shifted(_u32(data, sh + 16)))
    else:
        for item in loads:
            hdr = item["hdr_off"]
            if is64:
                struct.pack_into("<Q", data, hdr + 48, PAGE)
            else:
                struct.pack_into("<I", data, hdr + 28, PAGE)

    if not loads_ok(data):
        return "verify-failed"
    path.write_bytes(data)
    return "aligned"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    failed = 0
    for path in args.paths:
        status = align_elf(path)
        print(f"{path}: {status}")
        if status not in ("already", "aligned"):
            failed += 1
    return failed


if __name__ == "__main__":
    sys.exit(main())
