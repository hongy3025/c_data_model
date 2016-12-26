# encoding=utf-8

from __future__ import absolute_import
from struct import pack_into, unpack_from

INIT_BUFF_SIZE = 1024 * 4
MORE_BUFF_SPACE = '\0' * 1024

C_ARRAY_32 = chr(0xd0)
C_MAP_32 = chr(0xd1)
C_ID_MAP_32 = chr(0xd2)

class WriteBuffer(object):
    def __init__(self):
        self.b = bytearray(INIT_BUFF_SIZE)
        self.offset = 0

    def check_size(self, new_size):
        if len(self.b) < new_size:
            self.b.expand(MORE_BUFF_SPACE)

    def pull(self, n):
        '''扩展更多写空间。返回内部buffer对象和新扩展的空间偏移地址。'''
        new_offset = self.offset + n
        self.check_size(new_offset)
        offset = self.offset
        self.offset = new_offset
        return self.b, offset

    def tostring(self):
        return str(self.b[:self.offset])

class ReadBuffer(object):
    def __init__(self, src):
        self.b = memoryview(src)
        self.offset = 0

    def push(self, n):
        '''增加读缓冲区内的读偏移地址。返回内部buff对象和push前的读偏移地址。'''
        old_offset = self.offset
        new_offset = old_offset + n
        if new_offset > len(self.b):
            raise MemoryError('no more data')
        self.offset = new_offset
        return self.b, old_offset

    def is_end(self):
        return self.offset >= len(self.b)

def encode_int8(buf, value):
    b, offset = buf.pull(1)
    pack_into('!b', b, offset, value)

def encode_uint8(buf, value):
    b, offset = buf.pull(1)
    pack_into('!B', b, offset, value)

def encode_int16(buf, value):
    b, offset = buf.pull(2)
    pack_into('!h', b, offset, value)

def encode_uint16(buf, value):
    b, offset = buf.pull(2)
    pack_into('!H', b, offset, value)

def encode_int32(buf, value):
    b, offset = buf.pull(4)
    pack_into('!i', b, offset, value)

def encode_uint32(buf, value):
    b, offset = buf.pull(4)
    pack_into('!I', b, offset, value)

def encode_int64(buf, value):
    b, offset = buf.pull(8)
    pack_into('!q', b, offset, value)

def encode_uint64(buf, value):
    b, offset = buf.pull(8)
    pack_into('!Q', b, offset, value)

def encode_float(buf, value):
    b, offset = buf.pull(4)
    pack_into('!f', b, offset, value)

def encode_double(buf, value):
    b, offset = buf.pull(8)
    pack_into('!d', b, offset, value)

def encode_bool(buf, value):
    _value = 1 if value else 0
    b, offset = buf.pull(1)
    pack_into('!B', b, offset, _value)

def encode_string(buf, value):
    ssize = len(value)
    if ssize >= 2 ** 16:
        raise RuntimeError('length of string, %d' % ssize)
    b, offset = buf.pull(2 + len(value))
    pack_into('!H', b, offset, ssize)
    offset += 2
    fmt = str(ssize) + 's'
    pack_into(fmt, b, offset, value)

def encode_field_index(buf, index):
    b, offset = buf.pull(2)
    pack_into('!H', b, offset, index)

def encode_array_head(buf, size):
    b, offset = buf.pull(1)
    pack_into('c', b, offset, C_ARRAY_32)
    b, offset = buf.pull(4)
    pack_into('!I', b, offset, size)

def encode_map_head(buf, size):
    b, offset = buf.pull(1)
    pack_into('c', b, offset, C_MAP_32)
    b, offset = buf.pull(4)
    pack_into('!I', b, offset, size)

def encode_id_map_head(buf, size):
    b, offset = buf.pull(1)
    pack_into('c', b, offset, C_ID_MAP_32)
    b, offset = buf.pull(4)
    pack_into('!I', b, offset, size)

def decode_int8(buf):
    b, offset = buf.push(1)
    return unpack_from('!b', b, offset)[0]

def decode_uint8(buf):
    b, offset = buf.push(1)
    return unpack_from('!B', b, offset)[0]

def decode_int16(buf):
    b, offset = buf.push(2)
    return unpack_from('!h', b, offset)[0]

def decode_uint16(buf):
    b, offset = buf.push(2)
    return unpack_from('!H', b, offset)[0]

def decode_int32(buf):
    b, offset = buf.push(4)
    return unpack_from('!i', b, offset)[0]

def decode_uint32(buf):
    b, offset = buf.push(4)
    return unpack_from('!I', b, offset)[0]

def decode_int64(buf):
    b, offset = buf.push(8)
    return unpack_from('!q', b, offset)[0]

def decode_uint64(buf):
    b, offset = buf.push(8)
    return unpack_from('!Q', b, offset)[0]

def decode_float(buf):
    b, offset = buf.push(4)
    return unpack_from('!f', b, offset)[0]

def decode_double(buf):
    b, offset = buf.push(8)
    return unpack_from('!d', b, offset)[0]

def decode_bool(buf):
    b, offset = buf.push(1)
    value = unpack_from('!B', b, offset)[0]
    return True if value else False

def decode_string(buf):
    b, offset = buf.push(2)
    ssize = unpack_from('!H', b, offset)[0]
    b, offset = buf.push(ssize)
    fmt = str(ssize) + 's'
    return unpack_from(fmt, b, offset)[0]

def decode_field_index(buf):
    b, offset = buf.push(2)
    return unpack_from('!H', b, offset)[0]

def decode_array_head(buf):
    b, offset = buf.push(1)
    assert C_ARRAY_32 == unpack_from('c', b, offset)[0]
    b, offset = buf.push(4)
    return unpack_from('!I', b, offset)[0]

def decode_map_head(buf):
    b, offset = buf.push(1)
    assert C_MAP_32 == unpack_from('c', b, offset)[0]
    b, offset = buf.push(4)
    return unpack_from('!I', b, offset)[0]

def decode_id_map_head(buf):
    b, offset = buf.push(1)
    assert C_ID_MAP_32 == unpack_from('c', b, offset)[0]
    b, offset = buf.push(4)
    return unpack_from('!I', b, offset)[0]
