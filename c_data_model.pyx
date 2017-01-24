# encoding=utf-8

'''
 DataModel
===========

通过继承DataModel可以各种可持久化对象。
可持久化对象是表示，对象有pack和unpack方法。可以通过pack()调用将对象序列化成python dict或
二进制数据来保存，然后可以通过unpack()调用从python dict或二进制数据中回复对象原来的状态。

DataModel以下面这样的格式来定义对象里要存储和恢复的数据字段：

    class Point(DataModel):
        x = Field('int32', index=1)
        y = Field('int32', index=2)

    class Rect(DataModel):
        lt = Field(Point, index=1)
        rb = Field(Point, index=2)

上面的代码片段，定义了两个类：
=> Point有两个字段要存储：x, y，存储类型是int32；index号分别是1, 2；
=> Rect有两个字段要存储：lt, rb，存储类型是Point对象；这样Rect形成了嵌套的DataModel数据结构。

可以用下面的代码来初始化和引用Rect和Point里的字段：

    rect = Rect()
    rect.lt = Point(x=1, y=1)
    rect.rb = Point(x=100, y=101)
    rect.lt.x = 20
    yy = rect.lt.y

用pack(), unpack()方法来序列化，反序列化对象：

   result = rect.pack('dict')  # 将rect序列化为python dict格式数据
   >> result => {'lt': {'y': 1, 'x': 20}, 'rb': {'y': 101, 'x': 100}}
   rect2 = Rect()
   rect2.unpack('dict', result)  # 从python dict数据恢复对象状态
   result2 = rect2.pack('dict')  # result和results会有相同的内容
   >> result2 => {'lt': {'y': 1, 'x': 20}, 'rb': {'y': 101, 'x': 100}}

   result = rect.pack('bin')  # 将rect序列化位二进制格式

增量序列化
==========

DataModel某种程度上支持仅对对象数据有改变部分做序列化。即生成增量数据。例如：

    p = Point(x=1, y=0)
    p.y = 2
    result = p.pack('dict', only_changed=True)
    >> result => {'y': 2}   # 只有更改的y字段被序列化了

    rect = Rect(lt=Point(x=1, y=1), rb=Point(x=2, y=2))
    rect.lt.x = 100
    rect.rb.y = 100
    result = rect.pack('dict', only_changed=True)
    >> result => {'lt': {'x': 100}, 'rb': {'y': 100}}

支持数据类型
=============

DataModel用Field来定义字段的数据类型。支持的基本数据类型有：

    类型                      : 说明
    ---------------------------------------------
    int8                      : char
    uint8                     : unsigned char
    int16                     : short
    uint16                    : unsigned short
    int32                     : long
    uint32                    : unsigned long
    int64                     : long long
    uint64                    : unsigned long long
    float                     : float
    double                    : double
    bool                      : bool
    string                    : 变长字符串
    DataModel的子类           : -----

除了基本类型。DataModel还支持定义Array和Map，IdMap三种集合。Array和Map即数组和字典：

    class Polygon(DataModel):
        points = ArrayField(Point, 1)

    p = Polygon()
    p.points.append(Point(x=1, y=2))
    p.points.append(Point(x=3, y=4))

IdMap是一种比较特别的Map集合。它的value部分存储的是对象，而key部分存储的是对象的oid字
段的数值。

Field附加属性
==============

可以用附加属性来修饰Field，来帮助Field来更加精细的定义字段类型，标准的附加属性有：

    index   【必有】index属性用来定义字段的序号。DataModel在序列化成二进制数据的
             时候用index序号而不是字段名，来减少序列化后的数据大小。
    desc    【可选】字段描述
    arithm  【可选】如果有这个属性。DataModel自动为字段在类中添加add_xxx, sub_xxx
             两个函数。如果字段是无符号类型。sub_xxx函数会在发现会减成负数的时候抛
             出异常。
    default 【可选】字段的默认值。
    create  【可选】如果这个属性被设置。DataModel在恢复对象数据，构造字段的子对象
            时候，会调用create函数来构造，而不用默认的调用类名来构造对象。

    min_value    【可选】如果字段是数字类型，表示最小值取值范围。sub_xxx函数会在发
                  现将减少到比min_value更小的数值前抛出异常。
    skip_changed 【可选】表示这个被排除在增量变化检测之外。总是会被判定为无改变。

除了标准附加属性外，使用者可以给Field附加任意属性，来修饰字段类型的定义。这些附加属
性由使用者自己来使用和解释。


'''

include "codes_bin.pxi"

from functools import partial

# pylint: disable=protected-access,invalid-name,eval-used,too-many-branches,redefined-builtin
# pylint: disable=too-many-instance-attributes,too-many-statements,too-many-locals

class DataModelError(Exception):
    pass

class OperateError(DataModelError):
    pass

class DefineError(DataModelError):
    pass

class DuplicateIndexError(DataModelError):
    pass

class DuplicateNameError(DataModelError):
    pass

class NoFieldError(DataModelError):
    pass

class PackError(DataModelError):
    pass

class UnpackError(DataModelError):
    pass

class SkipFromPack(DataModelError):
    pass

SKIP_FROM_PACK = SkipFromPack()

cdef bint CONFIG_CHECK_INIT_ARGS = False

def set_CHECK_INIT_ARGS(value):
    CONFIG_CHECK_INIT_ARGS = value

# pylint: disable=bad-whitespace
cdef dict _default_values = {
    'int8'   : 0,
    'uint8'  : 0,
    'int16'  : 0,
    'uint16' : 0,
    'int32'  : 0,
    'uint32' : 0,
    'int64'  : 0,
    'uint64' : 0,
    'float'  : 0.0,
    'double' : 0.0,
    'bool'   : False,
    'string' : '',
}

cdef dict _value2string = {
    'int8'   : str,
    'uint8'  : str,
    'int16'  : str,
    'uint16' : str,
    'int32'  : str,
    'uint32' : str,
    'int64'  : str,
    'uint64' : str,
    'float'  : str,
    'double' : str,
    'bool'   : str,
    'string' : str,
}

cdef dict _string2value = {
    'int8'   : int,
    'uint8'  : int,
    'int16'  : int,
    'uint16' : int,
    'int32'  : int,
    'uint32' : int,
    'int64'  : int,
    'uint64' : int,
    'float'  : float,
    'double' : float,
    'bool'   : bool,
    'string' : str,
}
# pylint: enable=bad-whitespace

cdef set _number_types = set(['int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64', 'double', 'float'])
cdef set _unsigned_types = set(['uint8', 'uint16', 'uint32', 'uint64'])

cdef inline bint _exclude_oid_field(Field field):
    if field.name == 'oid':
        return False
    return True

cdef class FieldFilter:
    cdef set filters

    def __cinit__(self):
        self.filters = set()

    def __init__(self, *filters):
        for f in filters:
            if f is None:
                continue
            if isinstance(f, FieldFilter):
                self.filters.update((<FieldFilter>f).filters)
            else:
                self.filters.add(f)

    cdef bint is_filted(self, Field field):
        for f in self.filters:
            if not f(field):
                return True
        return False

cdef inline object _key_encode_to_string(str type_name, object encode):
    to_string = _value2string.get(type_name)
    assert to_string is not None
    def _converter(value):
        x = encode(value)
        return to_string(x)
    return _converter

cdef inline object _key_decode_from_string(str type_name, object decode):
    from_string = _string2value.get(type_name)
    assert from_string is not None
    def _converter(value):
        x = from_string(value)
        return decode(x)
    return _converter

cdef inline object _create_object(Field field, object cls, dict dict_data):
    if field.create:
        obj = field.create(dict_data)
    else:
        obj = cls()
    return obj

cdef inline void _replace_obj_dict(object obj, dict new_obj_dict):
    old_dict = obj.__dict__
    obj.__dict__ = new_obj_dict
    for k, v in old_dict.iteritems():
        if k not in new_obj_dict:
            new_obj_dict[k] = v

cdef inline str _value_short_repr(object value):
    if isinstance(value, DataModel):
        return value._short_repr_()
    info = str(value)
    if len(info) >= 32:
        info = info[:30] + '..'
    return info

cdef object _make_autogen_func_name(attrs, str op_prefix, str name):
    func_name = op_prefix + '_' + name
    if func_name in attrs:
        func_name = '_' + op_prefix + '_' + name
    return func_name

cdef inline object _dict_get_encoder(str type_name):
    if type_name in _default_values:
        if type_name == 'int8':
            return int
        if type_name == 'uint8':
            return int
        if type_name == 'int16':
            return int
        if type_name == 'uint16':
            return int
        if type_name == 'int32':
            return int
        if type_name == 'uint32':
            return int
        if type_name == 'int64':
            return int
        if type_name == 'uint64':
            return int
        if type_name == 'float':
            return float
        if type_name == 'double':
            return float
        if type_name == 'bool':
            return bool
        if type_name == 'string':
            return str
    return None

cdef inline object _dict_get_decoder(str type_name):
    if type_name in _default_values:
        if type_name == 'int8':
            return int
        if type_name == 'uint8':
            return int
        if type_name == 'int16':
            return int
        if type_name == 'uint16':
            return int
        if type_name == 'int32':
            return int
        if type_name == 'uint32':
            return int
        if type_name == 'int64':
            return int
        if type_name == 'uint64':
            return int
        if type_name == 'float':
            return float
        if type_name == 'double':
            return float
        if type_name == 'bool':
            return bool
        if type_name == 'string':
            return str
    return None

cdef inline object _bin_get_encoder(str type_name):
    if type_name in _default_values:
        if type_name == 'int8':
            return bin_encode_int8
        if type_name == 'uint8':
            return bin_encode_uint8
        if type_name == 'int16':
            return bin_encode_int16
        if type_name == 'uint16':
            return bin_encode_uint16
        if type_name == 'int32':
            return bin_encode_int32
        if type_name == 'uint32':
            return bin_encode_uint32
        if type_name == 'int64':
            return bin_encode_int64
        if type_name == 'uint64':
            return bin_encode_uint64
        if type_name == 'float':
            return bin_encode_float
        if type_name == 'double':
            return bin_encode_double
        if type_name == 'bool':
            return bin_encode_bool
        if type_name == 'string':
            return bin_encode_string
    return None

cdef inline object _bin_get_decoder(str type_name):
    if type_name in _default_values:
        if type_name == 'int8':
            return bin_decode_int8
        if type_name == 'uint8':
            return bin_decode_uint8
        if type_name == 'int16':
            return bin_decode_int16
        if type_name == 'uint16':
            return bin_decode_uint16
        if type_name == 'int32':
            return bin_decode_int32
        if type_name == 'uint32':
            return bin_decode_uint32
        if type_name == 'int64':
            return bin_decode_int64
        if type_name == 'uint64':
            return bin_decode_uint64
        if type_name == 'float':
            return bin_decode_float
        if type_name == 'double':
            return bin_decode_double
        if type_name == 'bool':
            return bin_decode_bool
        if type_name == 'string':
            return bin_decode_string
    return None

cdef inline void _mark_changed(int field_index, object self):
    _mark_changed_self_dict(field_index, self.__dict__)

cdef inline void _try_set_changed(object v):
    if isinstance(v, (DataModel, Array, Map)):
        v.set_changed()

cdef inline void _try_clear_changed(object v):
    if isinstance(v, (DataModel, Array, Map)):
        v.clear_changed()

cdef inline bint _try_check_changed(object v):
    if isinstance(v, (DataModel, Array, Map)):
        return v.has_changed()
    return False

cdef inline void _mark_changed_self_dict(int field_index, dict self_dict):
    cdef set changed_set = self_dict.setdefault('__changed_set__', set())
    changed_set.add(field_index)

cdef void _set_changed(object self, tuple field_names):
    cdef set change_set
    cdef dict _fields_by_name
    cdef str name
    cdef Field field

    if len(field_names) == 0:
        changed_set = self.__dict__.setdefault('__changed_set__', set())
        changed_set.add('*')
        return
    changed_set = self.__dict__.setdefault('__changed_set__', set())
    _fields_by_name = self._fields_by_name
    for name in field_names:
        field = _fields_by_name.get(name)
        if not field:
            raise NoFieldError('no such field: %s' % name)
        index = field.index
        changed_set.add(index)

cdef void _clear_field_changed(object self, Field field, dict self_dict, bint recursive):
    if not _can_clear_change(self, field):
        return

    cdef set changed_set = self_dict.get('__changed_set__', None)
    cdef dict _fields_is_container = self._fields_is_container

    cdef int field_index = field.index
    cdef str field_name = field.name
    cdef str field_key = field.key

    if changed_set:
        if field_index in changed_set:
            changed_set.remove(field_index)
        if '*' in changed_set:
            changed_set.remove('*')

    if _fields_is_container and (field_name in _fields_is_container):
        value = self_dict.get(field_key)
        if value is not None:
            if field.ref:
                value.clear_changed(recursive=False)
            else:
                value.clear_changed(recursive=recursive)
    elif field.is_data_model_type:
        if recursive:
            value = self_dict.get(field_key)
            if value is not None:
                _clear_changed(value, None, recursive)

cdef void _clear_changed(object self, tuple field_names, bint recursive=True):
    cdef Field field
    cdef dict self_dict = self.__dict__
    cdef dict _fields_by_name
    cdef str name
    if field_names:
        _fields_by_name = self._fields_by_name
        for name in field_names:
            field = _fields_by_name.get(name)
            if field:
                _clear_field_changed(self, field, self_dict, recursive)
    else:
        for field in self._fields:
            _clear_field_changed(self, field, self_dict, recursive)

cdef bint _has_field_changed(object self, Field field, bint recursive):
    if field.skip_changed:
        return False

    cdef dict self_dict = self.__dict__
    _fields_is_container = self._fields_is_container
    cdef set changed_set = self_dict.get('__changed_set__')

    if changed_set and ('*' in changed_set):
        return True

    cdef int field_index = field.index
    cdef str field_key = field.key
    cdef str field_name = field.name

    if _fields_is_container and (field_name in _fields_is_container):
        if changed_set and (field_index in changed_set):
            return True
        else:
            value = self_dict.get(field_key)
            if value is not None:
                if field.ref:
                    return value.has_changed(False)
                else:
                    return value.has_changed(recursive)
    elif field.is_data_model_type and (not field.ref):
        if changed_set and (field_index in changed_set):
            return True
        if recursive:
            value = self_dict.get(field_key)
            if value is not None:
                return _has_changed(value, recursive)
    else:
        if changed_set and (field_index in changed_set):
            return True

    return False

cdef inline bint _can_clear_change(object self, Field field):
    if field.skip_changed:
        return False
    return True

cdef inline bint _has_changed(object self, bint recursive=False):
    cdef Field field
    for field in self._fields:
        if _has_field_changed(self, field, recursive):
            return True
    return False

cdef inline bint _is_default_value(object self, str name):
    cdef Field field = self._fields_by_name.get(name)
    if not field:
        raise NoFieldError('no such field: %s' % name)
    cdef str key = field.key
    return self.__dict__.get(key) is None

def _fget(key, default, self):
    return self.__dict__.get(key, default)

def _fget_container(key, container_class, self):
    return self.__dict__.setdefault(key, container_class())

cdef _fset(key, field_index, self, value):
    if self.__dict__.get(key) != value:
        self.__dict__[key] = value
        _mark_changed(field_index, self)

cdef _fset_container(key, field_index, container_class, self, value):
    if isinstance(value, container_class):
        value.broadcast_changed()
        self.__dict__[key] = value
    else:
        value = container_class(value)
        value.broadcast_changed()
        self.__dict__[key] = value
    _mark_changed(field_index, self)

cdef _fdel(key, self):
    if hasattr(self, key):
        delattr(self, key)

cdef _fdel_container(key, self):
    raise OperateError('cannot del a container field')

cdef object _field_value_to_dict(encoder, Field field, object value,
                                 bint recursive, bint only_changed,
                                 bint clear_changed, FieldFilter field_filter,
                                 bint with_skip_from_pack=True):
    '''
    @memo:
        with_skip_from_pack 是否在打包的时候，返回由于增量打包，而导致没有任何数据输出的信息。
    '''
    cdef bint have_data
    if encoder:
        return encoder(value)
    elif recursive:
        if field.ref:
            return field.dict_ref_encoder(getattr(value, "oid", None))
        else:
            dict_data = {}
            have_data = _encode_to_dict(dict_data, field.value_type, value,
                                        recursive=recursive,
                                        only_changed=only_changed,
                                        clear_changed=clear_changed,
                                        field_filter=field_filter)
            if with_skip_from_pack:
                return dict_data if have_data else SKIP_FROM_PACK
            else:
                return dict_data

cdef bint _encode_to_dict(dict dict_data, object cls, object obj,
                          bint recursive, bint only_changed, bint clear_changed,
                          FieldFilter field_filter, object included_fields=None):
    '''将对象数据转储到dict'''
    cdef dict obj_dict = obj.__dict__

    cdef Field field
    cdef dict d
    cdef Map map_value
    cdef bint have_data = False if only_changed else True
    cdef object fvalue
    cdef FieldFilter i_field_filter

    for field in cls._fields:
        if included_fields is not None:
            if field.name not in included_fields:
                continue

        value = obj_dict.get(field.key)
        if value is None:
            continue

        if field_filter.is_filted(field):
            continue

        if only_changed:
            if not _has_field_changed(obj, field, recursive):
                continue

        encoder = field.dict_encoder
        kencoder = field.dict_key_encoder

        if field.array:
            dict_data[field.name] = [
                _field_value_to_dict(
                    encoder, field, v,
                    recursive=recursive,
                    only_changed=only_changed,
                    clear_changed=clear_changed,
                    field_filter=field_filter,
                    with_skip_from_pack=False)
                for v in value
            ]
            have_data = True
        elif field.map:
            d = dict_data[field.name] = {}
            map_value = value
            for k, v in map_value.iteritems():
                if only_changed:
                    if not map_value.is_item_changed(k, v):
                        continue
                key = kencoder(k)
                fvalue = _field_value_to_dict(
                    encoder, field, v,
                    recursive=recursive,
                    only_changed=only_changed,
                    clear_changed=clear_changed,
                    field_filter=field_filter)
                if fvalue is not SKIP_FROM_PACK:
                    d[key] = fvalue
                    have_data = True
            if only_changed:
                for key in map_value.get_removed_keys():
                    d[key] = None
                    have_data = True
        elif field.id_map:
            d = dict_data[field.name] = {}
            i_field_filter = FieldFilter(field_filter, _exclude_oid_field)
            for k, v in value.iteritems():
                if only_changed:
                    if not value.is_item_changed(k, v):
                        continue
                key = kencoder(v.oid)
                fvalue = _field_value_to_dict(
                    encoder, field, v,
                    recursive=recursive,
                    only_changed=only_changed,
                    clear_changed=clear_changed,
                    field_filter=i_field_filter)
                if fvalue is not SKIP_FROM_PACK:
                    d[key] = fvalue
                    have_data = True
            if only_changed:
                for key in value.get_removed_keys():
                    d[key] = None
                    have_data = True
        else:
            fvalue = _field_value_to_dict(
                encoder, field, value,
                recursive=recursive,
                only_changed=only_changed,
                clear_changed=clear_changed,
                field_filter=field_filter)
            if fvalue is not SKIP_FROM_PACK:
                dict_data[field.name] = fvalue
                have_data = True
    if clear_changed:
        _clear_changed(obj, None, recursive=False)

    return have_data

cdef inline _field_value_from_dict(decoder, field, dict_value, old_value, context):
    if decoder:
        return decoder(dict_value)
    else:
        return _field_object_from_dict(field, None, dict_value, old_value, context)

cdef _field_object_from_dict(Field field, oid, dict_value, old_value, DecodeContext context):
    if field.ref:
        return field.dict_ref_decoder(dict_value)
    else:
        if old_value is not None:
            fobj = old_value
            obj_dict = fobj.__dict__
        else:
            fobj = None
            obj_dict = {}
        fcls = field.value_type
        _decode_from_dict(fobj, fcls, obj_dict, dict_value, context)
        if fobj is None:
            fobj = _create_object(field, fcls, obj_dict)
            _replace_obj_dict(fobj, obj_dict)

        if oid is not None:
            fobj._oid = oid
        else:
            oid = obj_dict.get('_oid')
        context.add_known_object(oid, fobj)
        return fobj

cdef _decode_from_dict(obj, cls, obj_dict, dict_data, DecodeContext context):
    '''从dict_data恢复对象数据
        recursive       -> 是否递归子对象
        only_changed    -> 是否仅包含有改变的字段
    '''
    mark_change = context.mark_change

    cdef Field field
    for field in cls._fields:
        fname = field.name
        dvalue = dict_data.get(fname)
        if dvalue is None: # 数据容错：不解码为None的值
            continue
        decoder = field.dict_decoder
        kdecoder = field.dict_key_decoder
        field_key = field.key
        if field.array:
            arr = obj_dict[field_key] = field.container_class()
            for dv in dvalue:
                if not context.sync_mode:
                    if dv is None: # 数据容错：不解码为None的值
                        continue
                value = _field_value_from_dict(decoder, field, dv, None, context)
                arr._append(value)
                if field.ref:
                    context.add_unsolved_ref(('array', arr, len(arr) - 1, value))
        elif field.map:
            m = None
            if context.sync_mode:
                m = obj_dict.get(field_key)
            if m is None:
                m = field.container_class()
                obj_dict[field_key] = m
            for k, v in dvalue.iteritems():
                if not context.sync_mode:
                    if v is None:
                        continue # 数据容错：不解码为None的值
                old_value = None
                key = kdecoder(k)
                if context.sync_mode and v is None:
                    if key in m:
                        del m[key]
                    continue
                if context.sync_mode:
                    old_value = m.get(key)
                value = _field_value_from_dict(decoder, field, v, old_value, context)
                m._setitem(key, value)
                if field.ref:
                    context.add_unsolved_ref(('map', m, key, value))
        elif field.id_map:
            m = None
            if context.sync_mode:
                m = obj_dict.get(field_key)
            if m is None:
                m = field.container_class()
                obj_dict[field_key] = m
            for k, v in dvalue.iteritems():
                if not context.sync_mode:
                    if v is None:
                        continue # 数据容错：不解码为None的值
                old_value = None
                oid = kdecoder(k)
                if context.sync_mode and v is None:
                    if oid in m:
                        del m[oid]
                    continue
                if context.sync_mode:
                    old_value = m.get(oid)
                value = _field_object_from_dict(field, oid, v, old_value, context)
                m._setitem(oid, value)
                if field.ref:
                    context.add_unsolved_ref(('map', m, oid, value))
        else:
            old_value = None
            if context.sync_mode:
                old_value = obj_dict.get(field_key)
            value = _field_value_from_dict(decoder, field, dvalue, old_value, context)
            obj_dict[field_key] = value
            if field.ref:
                context.add_unsolved_ref(('obj_dict', obj_dict, field_key, value))

        if mark_change:
            _mark_changed_self_dict(field.index, obj_dict)


cdef _field_value_to_binary(
        buf, encoder, Field field, value, bint recursive,
        bint only_changed, bint clear_changed, field_filter=None):
    if encoder:
        encoder(buf, value)
    elif recursive:
        if field.ref:
            field.bin_ref_encoder(buf, value.oid)
        else:
            _encode_to_binary(buf, field.value_type, value,
                              recursive=recursive,
                              only_changed=only_changed,
                              clear_changed=clear_changed,
                              field_filter=field_filter)

cdef _encode_to_binary(buf, cls, obj, recursive, only_changed, clear_changed,
                       field_filter=None):
    '''将对象数据转储到binary buff。
        recursive       -> 是否递归子对象
        only_changed    -> 是否仅包含有改变的字段
    '''
    obj_dict = obj.__dict__

    cdef Field field
    for field in cls._fields:
        value = obj_dict.get(field.key)
        if value is None:
            continue

        if field_filter:
            if not field_filter(field):
                continue

        if only_changed:
            if not _has_field_changed(obj, field, recursive):
                continue

        encoder = field.bin_encoder
        kencoder = field.bin_key_encoder

        bin_encode_field_index(buf, field.index)
        if field.array:
            bin_encode_array_head(buf, len(value))
            for v in value:
                _field_value_to_binary(
                    buf, encoder, field, v,
                    recursive=recursive,
                    only_changed=only_changed,
                    clear_changed=clear_changed,
                    field_filter=field_filter)
        elif field.map:
            bin_encode_map_head(buf, len(value))
            for k, v in value.iteritems():
                kencoder(buf, k)
                _field_value_to_binary(
                    buf, encoder, field, v,
                    recursive=recursive,
                    only_changed=only_changed,
                    clear_changed=clear_changed,
                    field_filter=field_filter)
        elif field.id_map:
            bin_encode_id_map_head(buf, len(value))
            i_field_filter = FieldFilter(field_filter, _exclude_oid_field)
            for v in value.itervalues():
                k = v.oid
                kencoder(buf, k)
                _field_value_to_binary(
                    buf, encoder, field, v,
                    recursive=recursive,
                    only_changed=only_changed,
                    clear_changed=clear_changed,
                    field_filter=i_field_filter)
        else:
            _field_value_to_binary(
                buf, encoder, field, value,
                recursive=recursive,
                only_changed=only_changed,
                clear_changed=clear_changed,
                field_filter=field_filter)

    if clear_changed:
        _clear_changed(obj, None, recursive=False)

    bin_encode_field_index(buf, 0)

cdef _field_value_from_binary(buf, decoder, field, old_value, oid, context):
    if decoder:
        return decoder(buf)
    elif field.ref:
        return field.bin_ref_decoder(buf)
    else:
        if old_value is not None:
            fobj = old_value
            obj_dict = fobj.__dict__
        else:
            fobj = None
            obj_dict = {}
        fcls = field.value_type
        _decode_from_binary(buf, fobj, fcls, obj_dict, context)
        if fobj is None:
            fobj = _create_object(field, fcls, obj_dict)
            _replace_obj_dict(fobj, obj_dict)
        if oid is not None:
            fobj._oid = oid
            context.add_known_object(oid, fobj)
        return fobj

cdef _decode_from_binary(buf, obj, cls, obj_dict, context):
    '''从binary buff恢复对象数据'''
    mark_change = context.mark_change
    _fields_by_index = cls._fields_by_index

    while True:
        if buf.is_end():
            break
        field_index = bin_decode_field_index(buf)
        if field_index == 0:
            # end of field
            break
        field = _fields_by_index.get(field_index)
        if not field:
            raise PackError('unkown field, ndex={}'.format(field_index))
        decoder = field.bin_decoder
        kdecoder = field.bin_key_decoder
        field_key = field.key
        if field.array:
            arr = obj_dict[field_key] = field.container_class()
            asize = bin_decode_array_head(buf)
            for _ in xrange(asize):
                value = _field_value_from_binary(
                    buf, decoder, field, old_value=None,
                    oid=None, context=context)
                arr._append(value)  # 调用_append避免修改changed标志
                if field.ref:
                    context.add_unsolved_ref(('array', arr, len(arr) - 1, value))
        elif field.map:
            m = None
            if context.sync_mode:
                m = obj_dict.get(field_key)
            if m is None:
                m = field.container_class()
                obj_dict[field_key] = m
            asize = bin_decode_map_head(buf)
            for _ in xrange(asize):
                old_value = None
                key = kdecoder(buf)
                if context.sync_mode:
                    old_value = m.get(key)
                value = _field_value_from_binary(
                    buf, decoder, field, old_value=old_value,
                    oid=None, context=context)
                m._setitem(key, value)  # 调用_setitem避免修改changed标志
                if field.ref:
                    context.add_unsolved_ref(('map', m, key, value))
        elif field.id_map:
            m = None
            if context.sync_mode:
                m = obj_dict.get(field_key)
            if m is None:
                m = field.container_class()
                obj_dict[field_key] = m
            asize = bin_decode_id_map_head(buf)
            for _ in xrange(asize):
                old_value = None
                oid = kdecoder(buf)
                if context.sync_mode:
                    old_value = m.get(oid)
                value = _field_value_from_binary(
                    buf, decoder, field, old_value=old_value,
                    oid=oid, context=context)
                m._setitem(oid, value)  # 调用_setitem避免修改changed标志
                if field.ref:
                    context.add_unsolved_ref(('map', m, oid, value))
        else:
            old_value = None
            if context.sync_mode:
                old_value = obj_dict.get(field_key)
            value = _field_value_from_binary(
                buf, decoder, field, old_value=old_value,
                oid=None, context=context)
            obj_dict[field_key] = value
            if field.ref:
                context.add_unsolved_ref(('obj_dict', obj_dict, field_key, value))

        if mark_change:
            _mark_changed_self_dict(field_index, obj_dict)

cdef class DecodeContext(object):
    cdef dict known_objects
    cdef list tmp_unsolved_ref
    cdef dict unsolved_ref
    cdef object resolve_ref_func
    cdef bint mark_change
    cdef str mode
    cdef bint sync_mode

    def __cinit__(self, mode=None, resolve_ref=None, mark_change=False):
        self.known_objects = {}
        self.tmp_unsolved_ref = []
        self.unsolved_ref = {}
        self.mark_change = mark_change
        self.set_mode('override')
        if mode is not None:
            self.set_mode(mode)
        if resolve_ref is not None:
            self.resolve_ref_func = resolve_ref

    cdef set_mode(self, mode):
        if mode == 'sync':
            self.mode = 'sync'
            self.sync_mode = True
        else:
            self.mode = 'override'
            self.sync_mode = False

    cdef add_known_object(self, oid, obj):
        if self.resolve_ref_func is not None:
            return
        self.known_objects[oid] = obj

    cdef add_unsolved_ref(self, data):
        self.tmp_unsolved_ref.append(data)

    cdef resolve_ref(self):
        resolve_ref_func = self.resolve_ref_func
        if resolve_ref_func is not None:
            for _, container, k, v in self.tmp_unsolved_ref:
                obj = resolve_ref_func(v)
                if obj is None:
                    self.unsolved_ref[v] = True
                    continue
                container[k] = obj
        else:
            known_objects = self.known_objects
            for _, container, k, v in self.tmp_unsolved_ref:
                obj = known_objects.get(v)
                if obj is None:
                    self.unsolved_ref[v] = True
                    continue
                container[k] = obj

cdef class Array(list):
    cdef bint _changed

    def __cinit__(self, *arg, **kwargs):
        list.__init__(self, *arg, **kwargs)
        self._changed = False

    cpdef set_changed(self):
        self._changed = True

    cpdef has_changed(self, recursive=False):
        if self._changed:
            return self._changed
        if recursive:
            for value in self:
                if _try_check_changed(value):
                    return True
        return False

    cpdef clear_changed(self, recursive=False):
        self._changed = False
        if recursive:
            for value in self:
                _try_clear_changed(value)

    def __setitem__(self, k, v):
        self._changed = True
        self.broadcast_changed()
        list.__setitem__(self, k, v)

    def __delitem__(self, k):
        self._changed = True
        self.broadcast_changed()
        list.__delitem__(self, k)

    def __iadd__(self, other):
        self._changed = True
        self.broadcast_changed()
        return list.__iadd__(self, other)

    def __imul__(self, other):
        raise NotImplementedError('unsupport')

    def append(self, v):
        self._changed = True
        self.broadcast_changed()
        return list.append(self, v)

    cpdef _append(self, v):
        return list.append(self, v)

    def extend(self, v):
        self._changed = True
        self.broadcast_changed()
        return list.extend(self, v)

    def insert(self, k, v):
        self._changed = True
        self.broadcast_changed()
        return list.insert(self, k, v)

    def pop(self, k=None):
        self._changed = True
        self.broadcast_changed()
        if k is None:
            k = -1
        x = self[k]
        del self[k]
        return x

    def remove(self, x):
        self._changed = True
        self.broadcast_changed()
        list.remove(self, x)

    def sort(self, *arg, **kwargs):
        self._changed = True
        self.broadcast_changed()
        return list.sort(self, *arg, **kwargs)

    def broadcast_changed(self):
        for v in self:
            _try_set_changed(v)

cdef class Map(dict):
    cdef set _removed
    cdef set _changed

    def __cinit__(self, *arg, **kwargs):
        dict.__init__(self, *arg, **kwargs)
        self._removed = set()
        self._changed = set()

    cpdef void set_changed(self):
        self._changed.add('*')

    cpdef bint has_changed(self, bint recursive=False):
        if self._changed:
            return True
        if self._removed:
            return True
        if recursive:
            for value in self.itervalues():
                if _try_check_changed(value):
                    return True
        return False

    def clear_changed(self, recursive=False):
        self._changed.clear()
        self._removed.clear()
        if recursive:
            for value in self.itervalues():
                _try_clear_changed(value)

    def __setitem__(self, k, v):
        dict.__setitem__(self, k, v)
        _try_set_changed(v)
        self._changed.add(k)
        if k in self._removed:
            self._removed.remove(k)

    def __delitem__(self, k):
        dict.__delitem__(self, k)
        self._removed.add(k)
        if k in self._changed:
            self._changed.remove(k)

    def _setitem(self, k, v):
        dict.__setitem__(self, k, v)

    def clear(self):
        self._changed.clear()
        self._removed.update(self.iterkeys())
        return dict.clear(self)

    def pop(self, key, *args, **kwargs):
        cdef object v = dict.pop(self, key, *args, **kwargs)
        if key in self._changed:
            self._changed.remove(key)
        self._removed.add(key)
        return v

    def popitem(self):
        key, value = dict.popitem(self)
        if key in self._changed:
            self._changed.remove(key)
        self._removed.add(key)
        return (key, value)

    def setdefault(self, key, default=None):
        if default is None:
            default = self.value_field.value_type()
        self._changed.add(key)
        return dict.setdefault(self, key, default)

    def update(self, *arg, **kwargs):
        self.broadcast_changed()
        self._changed.add('*')
        return dict.update(self, *arg, **kwargs)

    def broadcast_changed(self):
        for v in self.itervalues():
            _try_set_changed(v)

    def get_removed_keys(self):
        return self._removed

    def is_item_changed(self, k, v):
        if k in self._changed:
            return True
        return _try_check_changed(v)


class IdMap(Map):
    def add(self, obj):
        self[obj.oid] = obj

    def remove(self, obj):
        key = obj.oid
        self._removed.add(key)
        del self[key]

    def has(self, obj):
        return obj.oid in self

cdef class Field(object):
    cdef str type_name
    cdef bint is_data_model_type
    cdef int index
    cdef object define_in_class
    cdef bint array
    cdef bint map
    cdef bint id_map
    cdef str key_type_name
    cdef object container_class
    cdef bint arithm
    cdef bint has_min_value
    cdef int min_value
    cdef bint is_unsigned
    cdef bint ref
    cdef bint skip_changed
    cdef object create
    cdef object default

    cdef object dict_encoder
    cdef object dict_decoder
    cdef object dict_key_encoder
    cdef object dict_key_decoder
    cdef object dict_ref_encoder
    cdef object dict_ref_decoder

    cdef object bin_encoder
    cdef object bin_decoder
    cdef object bin_key_encoder
    cdef object bin_key_decoder
    cdef object bin_ref_encoder
    cdef object bin_ref_decoder

    cdef dict __dict__

    property index:
        def __get__(self):
            return self.index

    def __cinit__(self, object typ, int index, bint array=False, bint map=False, bint id_map=False,
                  str key=None, object default=None, object min_value=None, bint arithm=False,
                  bint ref=False, bint skip_changed=False, **kwargs):
        self.value_type = None
        if isinstance(typ, (str, unicode)) and typ in _default_values:
            self.type_name = typ
            self.value_type = typ
            self.is_data_model_type = False
        elif issubclass(typ, DataModel):
            self.type_name = typ.__name__
            self.value_type = typ
            self.is_data_model_type = True
        else:
            raise DefineError('unsupported type')

        self.index = index
        if index <= 0 or index > 2 ** 16:
            raise DefineError('invalid index')

        self.define_in_class = None
        self.array = array
        self.key_type_name = key
        self.map = map
        self.id_map = id_map
        self.container_class = None
        self.arithm = arithm

        self.has_min_value = False
        self.min_value = 0
        if min_value is not None:
            self.has_min_value = True
            self.min_value = int(min_value)

        self.is_unsigned = True if self.type_name in _unsigned_types else False
        self.ref = ref
        self.skip_changed = skip_changed
        self.create = None

        self.__dict__.update(kwargs)

        self.default = None

        if default is not None:
            self.default = default
        else:
            self.default = _default_values.get(self.type_name)

        self.dict_encoder = _dict_get_encoder(self.type_name)
        self.dict_decoder = _dict_get_decoder(self.type_name)
        self.dict_key_encoder = None
        self.dict_key_decoder = None
        self.dict_ref_encoder = None
        self.dict_ref_decoder = None

        cdef Field value_field

        if self.ref:
            value_field = self.value_type._fields_by_name['oid']
            self.dict_ref_encoder = value_field.dict_encoder
            self.dict_ref_decoder = value_field.dict_decoder

        self.bin_encoder = _bin_get_encoder(self.type_name)
        self.bin_decoder = _bin_get_decoder(self.type_name)
        self.bin_key_encoder = None
        self.bin_key_decoder = None
        self.bin_ref_encoder = None
        self.bin_ref_decoder = None
        if self.ref:
            value_field = self.value_type._fields_by_name['oid']
            self.bin_ref_encoder = value_field.bin_encoder
            self.bin_ref_decoder = value_field.bin_decoder

        if [self, array, self.map, self.id_map].count(True) > 1:
            raise DefineError('conflicted properties: array, map, id_map')

        if self.array:
            self.container_class = type('Array_'+self.type_name,
                                        (Array,), {'value_field': self})
        elif self.map or self.id_map:
            if self.map:
                self.container_class = type('Map_'+self.type_name,
                                            (Map,), {'value_field': self})
            elif self.id_map:
                self.container_class = type('IdMap_'+self.type_name,
                                            (IdMap,), {'value_field': self})

            dict_key_encoder = _dict_get_encoder(self.key_type_name)
            assert dict_key_encoder
            self.dict_key_encoder = _key_encode_to_string(self.key_type_name, dict_key_encoder)

            dict_key_decoder = _dict_get_decoder(self.key_type_name)
            assert dict_key_decoder
            self.dict_key_decoder = _key_decode_from_string(self.key_type_name, dict_key_decoder)

            self.bin_key_encoder = _bin_get_encoder(self.key_type_name)
            assert self.bin_key_encoder
            self.bin_key_decoder = _bin_get_decoder(self.key_type_name)
            assert self.bin_key_decoder

    def is_container(self):
        return self.container_class is not None

    def __str__(self):
        return '<%s name=%s, index=%d, value_type=%s>' % (self.__class__.__name__, self.name, self.index, self.value_type)

    def __getattr__(self, name):
        return self.__dict__.get(name)

cdef _copy_any_base_fields(bases, _fields, _fields_by_index, _fields_by_name, _fields_by_key):
    for base in bases:
        if getattr(base, '_fields_by_index', None) is not None:
            _fields += base._fields[:]
            _fields_by_index.update(base._fields_by_index)
            _fields_by_name.update(base._fields_by_name)
            _fields_by_key.update(base._fields_by_key)
            return True
    for base in bases:
        if _copy_any_base_fields(base.__bases__, _fields, _fields_by_index,
                                 _fields_by_name, _fields_by_key):
            return True
    return False

class FieldsDefine(object):
    def __init__(self):
        self._fields = []
        self._fields_by_index = {}
        self._fields_by_name = {}
        self._fields_by_key = {}
        self._fields_is_container = {}

    def copy_bases_fields(self, bases):
        for base in bases:
            self.copy_class_fields(base)
            self.copy_bases_fields(base.__bases__)

    def set_define_in_class(self, cls):
        cdef Field field
        for field in self._fields:
            if field.define_in_class is None:
                field.define_in_class = cls

    def copy_class_fields(self, cls):
        cdef Field self_field
        cdef Field cls_field
        if getattr(cls, '_fields_by_index', None) is not None:
            # 确保index和name不重复
            for index in cls._fields_by_index:
                if index in self._fields_by_index:
                    self_field = self._fields_by_index[index]
                    cls_field = cls._fields_by_index[index]
                    if self_field.class_name != cls.__name__:
                        if self_field.define_in_class is not cls_field.define_in_class:
                            raise DuplicateIndexError(
                                "duplicate field index `%d' between class %s, %s"
                                % (index, self_field.class_name, cls.__name__))
            for name in cls._fields_by_name:
                if name in self._fields_by_name:
                    self_field = self._fields_by_name[name]
                    cls_field = cls._fields_by_name[name]
                    if self_field.class_name != cls.__name__:
                        if self_field.define_in_class is not cls_field.define_in_class:
                            raise DuplicateNameError(
                                "duplicate field name `%s' between class %s, %s" %
                                (name, self_field.class_name, cls.__name__))
            self._fields += cls._fields[:]
            self._fields_by_index.update(cls._fields_by_index)
            self._fields_by_name.update(cls._fields_by_name)
            self._fields_by_key.update(cls._fields_by_key)
            self._fields_is_container.update(cls._fields_is_container)


cdef _add_func(self, name, key, value):
    old_value = getattr(self, key, 0)
    new_value = old_value + value
    setattr(self, name, new_value)
    return value, new_value


def _make_get_func(key, default_type=None, default_value=None):
    if default_type is not None:
        def get_func(self):
            return self.__dict__.setdefault(key, default_type())
        return get_func
    else:
        def get_func(self):
            return self.__dict__.setdefault(key, default_value)
        return get_func


cdef object _make_add_func(str name, str key):
    def _add(object self, object value):
        old_value = getattr(self, key, 0)
        new_value = old_value + value
        setattr(self, name, new_value)
        return value, new_value
    return _add


cdef object _make_sub_func_with_min_value(str name, str key, object min_value):
    def _sub(object self, object value):
        old_value = getattr(self, key, 0)
        new_value = old_value - value
        if new_value < min_value:
            raise OverflowError('overflow lower limit')
        setattr(self, name, new_value)
        return old_value - new_value, new_value
    return _sub


cdef object _make_unsigned_sub_func(str name, str key):
    return _make_sub_func_with_min_value(name, key, 0)


cdef object _make_signed_sub_func(str name, str key):
    def _sub(object self, object value):
        old_value = getattr(self, key, 0)
        new_value = old_value - value
        setattr(self, name, new_value)
        return value, new_value
    return _sub


class MetaDataModel(type):
    def __new__(mcs, clsname, bases, _attrs):
        if clsname == 'DataModel':
            return type.__new__(mcs, clsname, bases, _attrs)

        cdef fields_define = FieldsDefine()

        fields_define.copy_bases_fields(bases)

        cdef this_fields_define = FieldsDefine()

        cdef dict attrs = dict(_attrs)

        cdef Field field

        for name, _field in _attrs.iteritems():
            if name.startswith('__'):
                continue
            if not isinstance(_field, Field):
                continue

            field = _field

            field.class_name = clsname

            key = '_' + name
            field.name = name
            field.key = key

            if field.is_container():
                attrs[name] = property(
                    partial(_fget_container, key, field.container_class),
                    partial(_fset_container, key, field.index, field.container_class),
                    partial(_fdel_container, key))
                get_func_name = _make_autogen_func_name(attrs, 'get', name)
                attrs[get_func_name] = _make_get_func(key, default_type=field.container_class)
            else:
                attrs[name] = property(
                    partial(_fget, key, field.default),
                    partial(_fset, key, field.index),
                    partial(_fdel, key))
                get_func_name = _make_autogen_func_name(attrs, 'get', name)
                if field.is_data_model_type:
                    attrs[get_func_name] = _make_get_func(key, default_type=field.value_type)
                else:
                    attrs[get_func_name] = _make_get_func(key, default_type=None, default_value=field.default)

            if field.arithm:
                if field.type_name not in _number_types:
                    raise TypeError('expect a number type')

                # 生成 add_`name' or _add_`name' 函数
                add_func_name = _make_autogen_func_name(attrs, 'add', name)
                attrs[add_func_name] = _make_add_func(name, key)

                # 生成 sub_`name' or _sub_`name' 函数
                sub_func_name = _make_autogen_func_name(attrs, 'sub', name)
                if field.has_min_value:
                    attrs[sub_func_name] = _make_sub_func_with_min_value(name, key, field.min_value)
                elif field.is_unsigned:
                    attrs[sub_func_name] = _make_unsigned_sub_func(name, key)
                else:
                    attrs[sub_func_name] = _make_signed_sub_func(name, key)

            this_fields_define._fields.append(field)
            this_fields_define._fields_by_index[field.index] = field
            this_fields_define._fields_by_name[name] = field
            this_fields_define._fields_by_key[key] = field
            if field.is_container():
                this_fields_define._fields_is_container[name] = field

            this_fields_define.__name__ = clsname

        fields_define.copy_class_fields(this_fields_define)

        newcls = type.__new__(mcs, clsname, bases, attrs)

        fields_define.set_define_in_class(newcls)

        newcls._fields = fields_define._fields
        newcls._fields.sort(lambda a, b: cmp(a.index, b.index))
        newcls._fields_by_index = fields_define._fields_by_index
        newcls._fields_by_name = fields_define._fields_by_name
        newcls._fields_by_key = fields_define._fields_by_key
        newcls._fields_is_container = fields_define._fields_is_container

        return newcls

class DataModel(object):
    __metaclass__ = MetaDataModel

    def __init__(self, **kwargs):
        self.set_data(**kwargs)

    def set_data(self, **kwargs):
        obj_dict = self.__dict__
        _fields_by_name = self._fields_by_name
        for name, value in kwargs.iteritems():
            field = _fields_by_name.get(name)
            if field:
                obj_dict[field.key] = value
            else:
                if CONFIG_CHECK_INIT_ARGS:
                    raise ValueError("unexpected field name `{}'".format(name))
                else:
                    obj_dict[name] = value

    def has_changed(self, field_name=None, recursive=False):
        if field_name:
            field = self._fields_by_name.get(field_name)
            if field is None:
                raise NoFieldError('no such field: %s' % field_name)
            return _has_field_changed(self, field, recursive)
        else:
            return _has_changed(self, recursive)

    def clear_changed(self, *field_names, **options):
        cdef bint recursive
        _recursive = options.get('recursive')
        if _recursive is None:
            recursive = True
        elif _recursive:
            recursive = True
        else:
            recursive = False
        return _clear_changed(self, field_names, recursive)

    def set_changed(self, *field_names):
        return _set_changed(self, field_names)

    def is_default_value(self, field_name):
        return _is_default_value(self, field_name)

    def clear_data(self):
        cdef Field field
        for field in self._fields:
            if hasattr(self, field.key):
                delattr(self, field.key)

    def pack_to_dict(self, recursive=True,
                     only_changed=False, clear_changed=False,
                     fields=None, field_filter=None):
        cdef dict dict_data = {}
        cdef FieldFilter ff
        if not isinstance(field_filter, FieldFilter):
            ff = FieldFilter(field_filter)
        else:
            ff = field_filter
        _encode_to_dict(dict_data, type(self), self,
                        recursive=recursive,
                        only_changed=only_changed,
                        clear_changed=clear_changed,
                        field_filter=ff,
                        included_fields=fields)
        return dict_data

    def unpack_from_dict(self, dict_data, mode=None, resolve_ref=None, mark_change=False):
        cdef DecodeContext context = DecodeContext(mode=mode, resolve_ref=resolve_ref, mark_change=mark_change)
        _decode_from_dict(self, type(self), self.__dict__, dict_data, context)
        context.resolve_ref()
        return context.unsolved_ref

    def get_changed_dict(self, recursive=False):
        return self.pack_to_dict(recursive, only_changed=True)

    def pack_to_binary(self, recursive=True, only_changed=False,
                       clear_changed=False, field_filter=None):
        buf = WriteBuffer()
        _encode_to_binary(buf, type(self), self,
                          recursive=recursive,
                          only_changed=only_changed,
                          clear_changed=clear_changed,
                          field_filter=field_filter)
        return buf.tostring()

    def unpack_from_binary(self, data, mode=None, resolve_ref=None, mark_change=False):
        buf = ReadBuffer(data)
        cdef context = DecodeContext(mode=mode, resolve_ref=resolve_ref, mark_change=mark_change)
        _decode_from_binary(buf, self, type(self), self.__dict__, context)
        context.resolve_ref()
        return context.unsolved_ref

    def pack(self, fmt, *args, **kwargs):
        if fmt == 'dict':
            return self.pack_to_dict(*args, **kwargs)
        elif fmt == 'bin':
            return self.pack_to_binary(*args, **kwargs)
        else:
            raise PackError('unsupported format: {}'.format(fmt))

    def unpack(self, fmt, *args, **kwargs):
        if fmt == 'dict':
            return self.unpack_from_dict(*args, **kwargs)
        elif fmt == 'bin':
            return self.unpack_from_binary(*args, **kwargs)
        else:
            raise PackError('unsupported format: {}'.format(fmt))

    def __str__(self):
        return self._long_repr_()

    def __repr__(self):
        return self._long_repr_()

    def _get_info_(self, nfields):
        array = []
        idx = 0
        while nfields > 0 and idx < len(self._fields):
            field = self._fields[idx]
            idx += 1
            if field.is_container():
                continue
            value = getattr(self, field.key, None)
            if value is not None:
                key = field.name
                info = '%s=%s' % (key, _value_short_repr(value))
                array.append(info)
                nfields -= 1
        obj_info = '%s(%s)' % (self.__class__.__name__, ','.join(array))
        return obj_info

    def _short_repr_(self):
        return self._get_info_(2)

    def _long_repr_(self):
        return self._get_info_(4)

def ArrayField(*arg, **kwarg):
    kwarg['array'] = True
    return Field(*arg, **kwarg)

def MapField(*arg, **kwarg):
    kwarg['map'] = True
    return Field(*arg, **kwarg)

def IdMapField(*arg, **kwarg):
    kwarg['id_map'] = True
    return Field(*arg, **kwarg)

