#!/usr/bin/env python3
import base64, os, struct, sys
from pathlib import Path

def rotl(v,n): return ((v << n) & 0xffffffff) | (v >> (32-n))
def qr(x,a,b,c,d):
    x[a]=(x[a]+x[b])&0xffffffff; x[d]^=x[a]; x[d]=rotl(x[d],16)
    x[c]=(x[c]+x[d])&0xffffffff; x[b]^=x[c]; x[b]=rotl(x[b],12)
    x[a]=(x[a]+x[b])&0xffffffff; x[d]^=x[a]; x[d]=rotl(x[d],8)
    x[c]=(x[c]+x[d])&0xffffffff; x[b]^=x[c]; x[b]=rotl(x[b],7)

def block(key,counter,nonce):
    c=b"expand 32-byte k"
    st=list(struct.unpack("<4I",c)+struct.unpack("<8I",key)+(counter,)+struct.unpack("<3I",nonce))
    x=st[:]
    for _ in range(10):
        qr(x,0,4,8,12); qr(x,1,5,9,13); qr(x,2,6,10,14); qr(x,3,7,11,15)
        qr(x,0,5,10,15); qr(x,1,6,11,12); qr(x,2,7,8,13); qr(x,3,4,9,14)
    return struct.pack("<16I", *[((x[i]+st[i])&0xffffffff) for i in range(16)])

def decrypt(data,key,nonce):
    out=bytearray(len(data)); ctr=1
    for off in range(0,len(data),64):
        ks=block(key,ctr,nonce); ctr += 1
        part=data[off:off+64]
        for i,b in enumerate(part): out[off+i]=b^ks[i]
    return bytes(out)

relay=Path(sys.argv[1])
out=Path(sys.argv[2])
key=base64.b64decode(sys.argv[3])
out.mkdir(parents=True,exist_ok=True)

for chunk in range(11):
    nonce=bytes([0x51,0x50,0x43,0x48,0x55,0x4e,0x4b,0x31,chunk,0,0,0])
    enc=base64.b64decode((relay/f"chunk{chunk}.b64").read_text().strip())
    plain=decrypt(enc,key,nonce)
    pos=0
    while pos < len(plain):
        path_len=struct.unpack(">I",plain[pos:pos+4])[0]; pos += 4
        rel=plain[pos:pos+path_len].decode("utf-8"); pos += path_len
        data_len=struct.unpack(">I",plain[pos:pos+4])[0]; pos += 4
        data=plain[pos:pos+data_len]; pos += data_len
        target=(out/rel).resolve()
        if not str(target).startswith(str(out.resolve())): raise RuntimeError("invalid path")
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(data)

print("decrypted",sum(1 for _ in out.rglob("*") if _.is_file()),"files")
