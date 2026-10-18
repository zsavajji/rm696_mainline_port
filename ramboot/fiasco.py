#!/usr/bin/env python3
"""Make a FIASCO image for Nokia's flasher from a stock RM-696 firmware, its kernel replaced:
  ramboot/fiasco.py FIRMWARE.bin IMAGE OUT.bin
then, on the computer with the flasher: flasher -F OUT.bin --flash-only=kernel -f -R
It keeps the firmware's header, its cert-sw entries (Nokia's signed certificates for each HW
revision, which NOLO wants before an image) and its ape-algo (the flasher's own flashing program,
which it won't flash without) and puts IMAGE in as the kernel: ~14 MB, flashes the kernel
partition alone. It carries Nokia's files: for the phone's owner, not for publishing.
The format, as Nokia's own entries are (checked on every entry read): entry = 0x54, the block
count, blocks (type, length, data), a checksum (0xff - the sum of the count and the blocks) and the
data. Block 0x2e: 01 01 00, the hash (XOR of the data's little-endian 16-bit words, stored big
endian), the type (12 bytes), the size (big endian) and 4 zero bytes. Nokia pads the kernel with
0xff to 128 bytes. (0xFFFF v0.10's -g writes entries its own reader rejects: an uncounted block.)"""
import struct, sys

def entries(f):
	"""(header, data offset, data size, type) of each entry, after the file header"""
	while (h := f.read(2)):
		assert h[0] == 0x54, f"no entry at {f.tell() - 2}"
		for _ in range(h[1]):
			t = f.read(2)
			h += t + f.read(t[1])
		ck = f.read(1)[0]
		assert ck == (0xff - sum(h[1:])) & 0xff, "checksum"
		assert h[2:4] == b"\x2e\x19"
		size = struct.unpack(">I", h[21:25])[0]
		yield h + bytes([ck]), f.tell(), size, h[9:21].rstrip(b"\0")
		f.seek(size, 1)

def kernel_entry(image):
	data = image + b"\xff" * (-len(image) % 128)
	h = 0
	for (w,) in struct.iter_unpack("<H", data):
		h ^= w
	blocks = b"\x2e\x19\x01\x01\x00" + struct.pack(">H", h) + b"kernel".ljust(12, b"\0") \
		+ struct.pack(">I", len(data)) + bytes(4)
	return b"\x54\x01" + blocks + bytes([(0xff - 1 - sum(blocks)) & 0xff]) + data

fw, image, out = sys.argv[1:]
with open(fw, "rb") as f, open(out, "wb") as o:
	assert f.read(1) == b"\xb4"
	n = f.read(4)
	o.write(b"\xb4" + n + f.read(struct.unpack(">I", n)[0]))
	for hdr, off, size, typ in list(entries(f)):
		if typ == b"kernel":
			o.write(kernel_entry(open(image, "rb").read()))
		elif typ in (b"cert-sw", b"ape-algo"):
			o.write(hdr)
			f.seek(off)
			while size:
				b = f.read(min(size, 1 << 24))
				o.write(b)
				size -= len(b)
