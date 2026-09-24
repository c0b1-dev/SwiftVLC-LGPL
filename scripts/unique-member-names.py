#!/usr/bin/env python3
"""
unique-member-names.py — give every object in libVLC's static libraries a unique name.

Why: `libvlc-full-static.a` bundles the objects of libVLC, its plugins and ~30 contribs, and
the same member name occurs more than once (ios-arm64: 366 names, 868 members; tvos-arm64:
331 names, 798 members). Some are the same helper object linked into several plugins, some
are different code that happens to share a file name (FFmpeg's `aes.o` beside libgcrypt's).
dsymutil finds an object by `libvlc.a(<name>)` and cannot tell same-named members apart: it
skips them ("skipping debug map object with duplicate name") or reads the wrong one ("could
not find symbol … in object file"). An app linking the engine therefore got ~300 warnings per
dSYM (Cobi Player: 317 of the 322 warnings of an Xcode Cloud test build, 295 per archive), and
its crash reports lost the debug info of every one of those objects.

What changes is ONLY the member names. The first member of a name keeps it; later ones become
`<stem>~2<ext>`, `<stem>~3<ext>`, … Payload bytes, header fields (date, owner, mode), member
order and the symbol table are kept. The symbol table's ENTRIES AND THEIR ORDER stay as they
are on purpose: 4925 symbols are defined by more than one member, and the table decides which
of those definitions the linker loads. Only its member offsets are rewritten, because a longer
name moves every member behind it. Regenerating the table (libtool, ranlib) would sort it and
could change that choice; this script never does.

Everything above is verified on the result before the original is replaced. An archive whose
names are already unique is left untouched, so running this twice is a no-op.

Measured on the 2026-09-07 build: relinking Cobi Player against the original and the rewritten
archive gives byte-identical sections (65 of 65, Debug simulator and Release device); dsymutil
goes from 317 (Debug) / 295 (Release) warnings to 0, and the dSYM grows by ~9 MB of engine
debug info that was skipped before.

Usage:
  ./scripts/unique-member-names.py Vendor/libvlc.xcframework
  ./scripts/unique-member-names.py path/to/libvlc.a [...]
"""
import collections
import os
import struct
import subprocess
import sys
import tempfile

MAGIC = b"!<arch>\n"
SYMDEFS = ("__.SYMDEF", "__.SYMDEF SORTED")


class Member:
    __slots__ = ("index", "name", "offset", "data_offset", "size", "mtime", "uid", "gid", "mode")


def read_members(buf, path):
    """Members of a THIN Darwin archive, in order, with their real (`#1/<len>`) names."""
    if not buf.startswith(MAGIC):
        sys.exit(f"{path}: not a thin static archive")
    members, pos = [], len(MAGIC)
    while pos < len(buf):
        hdr = buf[pos:pos + 60]
        if len(hdr) < 60 or hdr[58:60] != b"`\n":
            sys.exit(f"{path}: malformed member header at offset {pos}")
        field = hdr[0:16].decode("ascii").rstrip(" ")
        size = int(hdr[48:58])
        name_len = int(field[3:]) if field.startswith("#1/") else 0
        m = Member()
        m.index, m.offset = len(members), pos
        m.name = (buf[pos + 60:pos + 60 + name_len].rstrip(b"\0").decode("utf-8")
                  if name_len else field.rstrip("/"))
        m.data_offset, m.size = pos + 60 + name_len, size - name_len
        m.mtime, m.uid, m.gid = int(hdr[16:28]), int(hdr[28:34]), int(hdr[34:40])
        m.mode = int(hdr[40:48], 8)
        members.append(m)
        pos += 60 + size
        pos += pos % 2  # members start at even offsets
    return members


def symdef_entries(buf, m):
    """(string index, member header offset) pairs of a 32-bit ranlib table, in table order."""
    nbytes = struct.unpack_from("<I", buf, m.data_offset)[0]
    return [struct.unpack_from("<II", buf, m.data_offset + 4 + 8 * i) for i in range(nbytes // 8)]


def unique_names(names):
    taken, seen, out = set(names), collections.Counter(), []
    for name in names:
        seen[name] += 1
        if seen[name] == 1:
            out.append(name)
            continue
        stem, dot, ext = name.rpartition(".")
        stem, suffix = (stem, dot + ext) if dot else (name, "")
        k = seen[name]
        while f"{stem}~{k}{suffix}" in taken:
            k += 1
        out.append(f"{stem}~{k}{suffix}")
        taken.add(out[-1])
    return out


def header(m, name_field_len, payload_len):
    h = (f"#1/{name_field_len}".ljust(16) + str(m.mtime).ljust(12) + str(m.uid).ljust(6)
         + str(m.gid).ljust(6) + format(m.mode, "o").ljust(8)
         + str(name_field_len + payload_len).ljust(10)).encode("ascii") + b"`\n"
    assert len(h) == 60
    return h


def rewrite_thin(src, dst):
    """Returns the number of renamed members, or 0 (and writes nothing) if none needed it."""
    buf = open(src, "rb").read()
    members = read_members(buf, src)
    if not members or members[0].name not in SYMDEFS:
        sys.exit(f"{src}: expected a 32-bit symbol table first, found "
                 f"{members[0].name if members else 'nothing'!r}")
    objects = members[1:]
    new_names = [members[0].name] + unique_names([m.name for m in objects])
    renamed = sum(m.name != n for m, n in zip(members, new_names))
    if not renamed:
        return 0

    # Layout: every payload starts 8-byte aligned, as libtool writes it (the name field is
    # padded with at least four NULs up to that boundary).
    layout, new_offset, pos = [], {}, len(MAGIC)
    for m, name in zip(members, new_names):
        raw = name.encode("utf-8")
        name_len = len(raw) + 4
        while (pos + 60 + name_len) % 8:
            name_len += 1
        new_offset[m.offset] = pos
        layout.append((m, raw, name_len))
        pos += 60 + name_len + m.size
        if pos % 2:
            sys.exit(f"{src}: odd payload size in {m.name!r} — layout not handled")

    out = bytearray(MAGIC)
    for m, raw, name_len in layout:
        payload = buf[m.data_offset:m.data_offset + m.size]
        if m.index == 0:
            table = bytearray(payload)
            for i, (strx, off) in enumerate(symdef_entries(buf, m)):
                struct.pack_into("<II", table, 4 + 8 * i, strx, new_offset[off])
            payload = bytes(table)
        out += header(m, name_len, len(payload)) + raw + b"\0" * (name_len - len(raw)) + payload
    with open(dst, "wb") as f:
        f.write(out)

    verify(src, buf, members, new_names, dst)
    return renamed


def verify(src, old_buf, old, new_names, dst):
    buf = open(dst, "rb").read()
    new = read_members(buf, dst)

    def fail(why):
        sys.exit(f"{src}: verification failed — {why}")

    if len(new) != len(old):
        fail(f"{len(new)} members instead of {len(old)}")
    for a, b, name in zip(old, new, new_names):
        if b.name != name:
            fail(f"member {b.index} is {b.name!r}, expected {name!r}")
        if (a.mtime, a.uid, a.gid, a.mode) != (b.mtime, b.uid, b.gid, b.mode):
            fail(f"header fields of member {b.index} changed")
        if b.data_offset % 8:
            fail(f"member {b.index} is not 8-byte aligned")
        if a.index and old_buf[a.data_offset:a.data_offset + a.size] != buf[b.data_offset:b.data_offset + b.size]:
            fail(f"payload of member {b.index} ({a.name!r}) changed")
    names = [m.name for m in new[1:]]
    if len(set(names)) != len(names):
        fail("member names are still not unique")
    # The symbol table: same entries, same order, each naming the member with the same index,
    # and the same string table.
    old_entries, new_entries = symdef_entries(old_buf, old[0]), symdef_entries(buf, new[0])
    old_index = {m.offset: m.index for m in old}
    new_index = {m.offset: m.index for m in new}
    if len(old_entries) != len(new_entries):
        fail("symbol table has a different number of entries")
    for (sa, oa), (sb, ob) in zip(old_entries, new_entries):
        if sa != sb or old_index.get(oa) != new_index.get(ob):
            fail("a symbol table entry points at a different member")
    strings = 4 + 8 * len(old_entries)
    if old_buf[old[0].data_offset + strings:old[0].data_offset + old[0].size] != \
            buf[new[0].data_offset + strings:new[0].data_offset + new[0].size]:
        fail("symbol string table changed")


def archs(path):
    return subprocess.run(["lipo", "-archs", path], check=True, capture_output=True,
                          text=True).stdout.split()


def process_library(lib):
    lib_archs = archs(lib)
    with tempfile.TemporaryDirectory(dir=os.path.dirname(os.path.abspath(lib))) as work:
        fat = len(lib_archs) > 1
        thin_out, renamed = [], {}
        for arch in lib_archs:
            thin = os.path.join(work, f"{arch}.a")
            if fat:
                subprocess.run(["lipo", "-thin", arch, lib, "-output", thin], check=True)
            else:
                thin = lib
            out = os.path.join(work, f"{arch}.unique.a")
            renamed[arch] = rewrite_thin(thin, out)
            thin_out.append(out if renamed[arch] else thin)
        if not any(renamed.values()):
            print(f"  {lib}: names already unique ({', '.join(lib_archs)})")
            return
        result = os.path.join(work, "libvlc.a")
        if fat:
            subprocess.run(["lipo", "-create", *thin_out, "-output", result], check=True)
        else:
            os.replace(thin_out[0], result)
        if archs(result) != lib_archs:
            sys.exit(f"{lib}: architectures changed ({archs(result)} vs {lib_archs})")
        os.chmod(result, os.stat(lib).st_mode & 0o7777)
        os.replace(result, lib)
    detail = ", ".join(f"{a}: {n} renamed" for a, n in renamed.items())
    print(f"  {lib}: {detail}")


def main(paths):
    if not paths:
        sys.exit(__doc__.split("Usage:")[1].rstrip())
    for path in paths:
        if os.path.isdir(path) and path.rstrip("/").endswith(".xcframework"):
            libs = sorted(os.path.join(root, f) for root, _, files in os.walk(path)
                          for f in files if f.endswith(".a"))
            if not libs:
                sys.exit(f"{path}: no static libraries inside")
            for lib in libs:
                process_library(lib)
        elif os.path.isfile(path) and path.endswith(".a"):
            process_library(path)
        else:
            sys.exit(f"{path}: expected an .xcframework directory or an .a file")


if __name__ == "__main__":
    main(sys.argv[1:])
