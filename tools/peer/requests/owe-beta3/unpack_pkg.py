"""Unpack a WE scene.pkg into a folder: u32-length header string, u32 count, then (u32 name len, name, u32 offset, u32 size) per entry; data follows."""
import os, struct, sys

def unpack(pkg, out):
    d = open(pkg, "rb").read()
    o = 0
    def u32():
        nonlocal o; v = struct.unpack_from("<I", d, o)[0]; o += 4; return v
    def s():
        nonlocal o; n = u32(); v = d[o:o + n].decode("utf-8", "replace"); o += n; return v
    magic = s(); n = u32()
    ents = [(s(), u32(), u32()) for _ in range(n)]
    base = o
    for name, off, size in ents:
        p = os.path.join(out, name.replace("/", os.sep)); os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(d[base + off: base + off + size])
    return magic, len(ents)

if __name__ == "__main__":
    print(unpack(sys.argv[1], sys.argv[2]))
