"""Rewrite a WE scene.pkg with one entry replaced. Layout: str header, int count, [str name, int offset, int length]*, data."""
import struct, sys


def read(path):
    b = open(path, "rb").read(); p = 0
    def i32():
        nonlocal p; v = struct.unpack_from("<i", b, p)[0]; p += 4; return v
    def s():
        nonlocal p; n = i32(); v = b[p:p + n]; p += n; return v
    hdr = s(); n = i32(); ents = [(s(), i32(), i32()) for _ in range(n)]
    base = p
    return hdr, [(name, b[base + off:base + off + ln]) for name, off, ln in ents]


def write(path, hdr, files):
    out = bytearray(struct.pack("<i", len(hdr)) + hdr + struct.pack("<i", len(files)))
    off = 0
    for name, data in files:
        out += struct.pack("<i", len(name)) + name + struct.pack("<ii", off, len(data)); off += len(data)
    for _, data in files:
        out += data
    open(path, "wb").write(out)


if __name__ == "__main__":
    pkg, entry, newfile = sys.argv[1:4]
    hdr, files = read(pkg)
    new = open(newfile, "rb").read()
    files = [(n, new if n.decode() == entry else d) for n, d in files]
    write(pkg, hdr, files)
    hdr2, files2 = read(pkg)
    print("rewritten:", pkg, "| entries", len(files2), "| scene.json has sorting false:",
          b'"transparentsorting" : false' in dict(files2)[entry.encode()])
