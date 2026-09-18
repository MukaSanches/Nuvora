#!/usr/bin/env python3
import base64, json, os, sys
from pathlib import Path

MASK = 0xffffffff

def rotl(v, n):
    return ((v << n) & MASK) | (v >> (32 - n))

def qr(x, a, b, c, d):
    x[a] = (x[a] + x[b]) & MASK; x[d] ^= x[a]; x[d] = rotl(x[d], 16)
    x[c] = (x[c] + x[d]) & MASK; x[b] ^= x[c]; x[b] = rotl(x[b], 12)
    x[a] = (x[a] + x[b]) & MASK; x[d] ^= x[a]; x[d] = rotl(x[d], 8)
    x[c] = (x[c] + x[d]) & MASK; x[b] ^= x[c]; x[b] = rotl(x[b], 7)

def word(b, off):
    return int.from_bytes(b[off:off+4], "little")

def chacha_block(key, counter, nonce):
    state = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
    state += [word(key, i * 4) for i in range(8)]
    state += [counter & MASK]
    state += [word(nonce, i * 4) for i in range(3)]
    x = state.copy()
    for _ in range(10):
        qr(x,0,4,8,12); qr(x,1,5,9,13); qr(x,2,6,10,14); qr(x,3,7,11,15)
        qr(x,0,5,10,15); qr(x,1,6,11,12); qr(x,2,7,8,13); qr(x,3,4,9,14)
    out = bytearray()
    for a, b in zip(x, state):
        out.extend(((a + b) & MASK).to_bytes(4, "little"))
    return bytes(out)

def decrypt(data, key, nonce):
    out = bytearray(len(data))
    counter = 1
    for off in range(0, len(data), 64):
        ks = chacha_block(key, counter, nonce)
        counter += 1
        chunk = data[off:off+64]
        for i, value in enumerate(chunk):
            out[off+i] = value ^ ks[i]
    return bytes(out)

overlay_dir = Path(sys.argv[1])
workspace = Path(sys.argv[2])
key = bytes.fromhex(sys.argv[3])
if len(key) != 32:
    raise SystemExit("QP_BUILD_KEY_V180 must be 32-byte hex")
manifest = json.loads((overlay_dir / "manifest.json").read_text(encoding="utf-8"))
for item in manifest:
    data = base64.b64decode((overlay_dir / item["file"]).read_text(encoding="utf-8"))
    plain = decrypt(data, key, bytes.fromhex(item["nonce"]))
    target = workspace / item["path"]
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(plain)
print(f"Applied {len(manifest)} encrypted Quick Print 1.8.0 overlays")
