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

cimport cython
from cpython.method cimport PyMethod_New
cimport cython_metaclass

cdef extern from "field_dirty_set.h":
    ctypedef unsigned short FieldIdx
    cdef cppclass FieldDirtySet:
        bint is_dirty(FieldIdx f)
        void set_dirty(FieldIdx f, bint value)
        void clear_dirty(FieldIdx f)
        void clear_all()

ctypedef long long int64
ctypedef unsigned long long uint64


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

cdef object SKIP_FROM_PACK = SkipFromPack()


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

cdef set _int_types = set(('int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64'))
cdef set _unsigned_int_types = set(('uint8', 'uint16', 'uint32', 'uint64'))


cdef inline bint _exclude_oid_field(Field field):
    if field.name == 'oid':
        return False
    return True


cdef class FieldFilter(object):
    cdef set filters

    def __cinit__(self, *filters):
        self.filters = set()
        for f in filters:
            if not f:
                continue
            if isinstance(f, FieldFilter):
                self.filters.update(f.filters)
            else:
                self.filters.add(f)

    def __call__(self, field):
        for f in self.filters:
            if not f(field):
                return False
        return True


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


cdef str make_autogen_func_name(attrs, str op_prefix, str name):
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


cdef inline void _mark_changed(int field_index, object self):
    _mark_changed_self_dict(field_index, self.__dict__)


cdef inline void _try_set_changed(object v):
    if isinstance(v, (DataModel, Array, Map)):
        v.set_changed()


cdef inline void _broadcast_changed(object v):
    if isinstance(v, Array):
        (<Array>v).broadcast_changed()
    elif isinstance(v, Map):
        (<Map>v).broadcast_changed()


cdef inline void _container_clear_changed(Field field, object v, bint recursive):
    if field.array:
        (<Array>v)._clear_changed(recursive)
    elif field.map or field.id_map:
        (<Map>v)._clear_changed(recursive)


cdef inline bint _try_clear_changed(Field field, object v, bint recursive):
    if field.is_container():
        _container_clear_changed(field, v, recursive)
    elif field.is_data_model_type():
        (<DataModel>v)._clear_changed(None, recursive)


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

#
# cdef void _clear_field_changed(object self, Field field, dict self_dict, bint recursive):
#     if not _can_clear_change(self, field):
#         return
# 
#     cdef set changed_set = self_dict.get('__changed_set__', None)
#     cdef dict _fields_is_container = self._fields_is_container
# 
#     cdef int field_index = field.index
#     cdef str field_name = field.name
#     cdef str field_key = field.key
# 
#     if changed_set:
#         if field_index in changed_set:
#             changed_set.remove(field_index)
#         if '*' in changed_set:
#             changed_set.remove('*')
# 
#     if _fields_is_container and (field_name in _fields_is_container):
#         value = self_dict.get(field_key)
#         if value is not None:
#             if field.ref:
#                 value.clear_changed(False)
#             else:
#                 value.clear_changed(recursive)
#     elif field.is_data_model_type():
#         if recursive:
#             value = self_dict.get(field_key)
#             if value is not None:
#                 _clear_changed(value, None, recursive)
# 
# 
# cdef void _clear_changed(object self, tuple field_names, bint recursive=True):
#     cdef Field field
#     cdef dict self_dict = self.__dict__
#     cdef dict _fields_by_name
#     cdef str name
#     if field_names:
#         _fields_by_name = self._fields_by_name
#         for name in field_names:
#             field = _fields_by_name.get(name)
#             if field:
#                 _clear_field_changed(self, field, self_dict, recursive)
#     else:
#         for field in self._fields:
#             _clear_field_changed(self, field, self_dict, recursive)


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
    elif field.is_data_model_type() and (not field.ref):
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


cdef object make_fget(Field field):
    def fget(object self):
        return self.__dict__.get(field.key, field.default)
    return fget


cdef object make_fset(Field field):
    def fset(object self, object value):
        if self.__dict__.get(field.key) != value:
            self.__dict__[field.key] = value
            _mark_changed(field.index, self)
    return fset


cdef object make_fdel(Field field):
    def fdel(object self):
        if hasattr(self, Field.key):
            delattr(self, Field.key)
        # TODO: set dirty ?
    return fdel


cdef object _field_value_to_dict(encoder, Field field, object value,
                                 bint recursive, bint only_changed,
                                 bint clear_changed, object field_filter=None,
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
            have_data = _encode_to_dict(dict_data,
                                        field.data_model_protocol,
                                        value,
                                        recursive=recursive,
                                        only_changed=only_changed,
                                        clear_changed=clear_changed,
                                        field_filter=field_filter)
            if with_skip_from_pack:
                return dict_data if have_data else SKIP_FROM_PACK
            else:
                return dict_data


cdef bint _encode_to_dict(dict dict_data, DataModelProtocol protocol, object obj,
                          bint recursive, bint only_changed, bint clear_changed,
                          object field_filter=None):
    '''将对象数据转储到dict'''
    cdef dict obj_dict = obj.__dict__

    cdef Field field
    cdef dict d
    cdef Map map_value
    cdef bint have_data = False if only_changed else True
    cdef object fvalue

    for field in protocol.fields_define.fields:
        value = obj_dict.get(field.key)
        if value is None:
            continue

        if field_filter:
            if not field_filter(field):
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
                key = kencoder(k)
                fvalue = _field_value_to_dict(
                    encoder, field, v,
                    recursive=recursive,
                    only_changed=only_changed,
                    clear_changed=clear_changed,
                    field_filter=field_filter)
                if fvalue != SKIP_FROM_PACK:
                    d[key] = fvalue
                    have_data = True
            if only_changed:
                for key in map_value._removed:
                    d[key] = None
                    have_data = True
        elif field.id_map:
            d = dict_data[field.name] = {}
            i_field_filter = FieldFilter(field_filter, _exclude_oid_field)
            for _, v in value.iteritems():
                key = kencoder(v.oid)
                fvalue = _field_value_to_dict(
                    encoder, field, v,
                    recursive=recursive,
                    only_changed=only_changed,
                    clear_changed=clear_changed,
                    field_filter=i_field_filter)
                if fvalue != SKIP_FROM_PACK:
                    d[key] = fvalue
                    have_data = True
                d[key] = fvalue
            if only_changed:
                for key in value._removed:
                    d[key] = None
                    have_data = True
        else:
            fvalue = _field_value_to_dict(
                encoder, field, value,
                recursive=recursive,
                only_changed=only_changed,
                clear_changed=clear_changed,
                field_filter=field_filter)
            if fvalue != SKIP_FROM_PACK:
                dict_data[field.name] = fvalue
                have_data = True
    if clear_changed:
        (<DataModel>obj)._clear_changed(None, recursive=False)

    return have_data


cdef inline object _field_value_from_dict(Field field, object decoder,
                                          object dict_value, object old_value,
                                          DecodeContext context):
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


cdef void _decode_from_dict(DataModelProtocol protocol,
                            object obj, dict obj_dict,
                            dict src_dict_data,
                            DecodeContext context):
    '''从src_dict_data恢复对象数据
        recursive       -> 是否递归子对象
        only_changed    -> 是否仅包含有改变的字段
    '''
    mark_change = context.mark_change

    cdef Field field
    cdef object dvalue
    cdef object decoder
    cdef object kdecoder
    cdef object old_value
    cdef DataModel dm_obj

    for field in protocol.fields_define.fields:
        dvalue = src_dict_data.get(field.name)
        if dvalue is None: # 数据容错：不解码为None的值
            continue
        decoder = field.dict_decoder
        kdecoder = field.dict_key_decoder
        if field.array:
            arr = obj_dict[field.key] = field.container_class()
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
                m = obj_dict.get(field.key)
            if m is None:
                m = field.container_class()
                obj_dict[field.key] = m
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
                m = obj_dict.get(field.key)
            if m is None:
                m = field.container_class()
                obj_dict[field.key] = m
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
                old_value = obj_dict.get(field.key)
            value = _field_value_from_dict(field, decoder, dvalue, old_value, context)
            obj_dict[field.key] = value
            if field.ref:
                context.add_unsolved_ref(('obj_dict', obj_dict, field.key, value))

        if mark_change:
            dm_obj = <DataModel>obj
            dm_obj._mark_field_changed(field)


cdef class DecodeContext(object):
    cdef dict known_objects
    cdef list tmp_unsolved_ref
    cdef dict unsolved_ref
    cdef object resolve_ref_func
    cdef bint mark_change
    cdef str mode
    cdef bint sync_mode


    def __cinit__(self, str mode=None, object resolve_ref=None, bint mark_change=False):
        self.known_objects = {}
        self.tmp_unsolved_ref = []
        self.unsolved_ref = {}
        self.mark_change = mark_change
        self.set_mode('override')
        if mode is not None:
            self.set_mode(mode)
        if resolve_ref is not None:
            self.resolve_ref_func = resolve_ref


    cdef void set_mode(self, mode):
        if mode == 'sync':
            self.mode = 'sync'
            self.sync_mode = True
        else:
            self.mode = 'override'
            self.sync_mode = False


    cdef void add_known_object(self, str oid, object obj):
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
        #if recursive:
            #for value in self:
                #if _try_check_changed(value):
                    #return True
        return False


    cdef _clear_changed(self, recursive=False):
        self._changed = False
        # if recursive:
        #     for value in self:
        #         _try_clear_changed(value)


    def clear_changed(self, recursive=False):
        self._clear_changed(recursive)


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
            return list.pop(self)
        else:
            return list.pop(self, k)


    def remove(self, x):
        self._changed = True
        self.broadcast_changed()
        return list.remove(self, x)


    def sort(self, *arg, **kwargs):
        self._changed = True
        self.broadcast_changed()
        return list.sort(self, *arg, **kwargs)


    cdef broadcast_changed(self):
        for v in self:
            _try_set_changed(v)


cdef class Map(dict):
    cdef set _removed
    cdef bint _changed


    def __cinit__(self, *arg, **kwargs):
        dict.__init__(self, *arg, **kwargs)
        self._removed = set()
        self._changed = False


    cpdef void set_changed(self):
        self._changed = True


    cpdef bint has_changed(self, bint recursive=False):
        if self._changed:
            return self._changed
        #if recursive:
            #for value in self.itervalues():
                #if _try_check_changed(value):
                    #return True
        return False


    cdef inline void _clear_changed(self, bint recursive=False):
        self._changed = False
        self._removed.clear()
        #if recursive:
            #for value in self.itervalues():
                #_try_clear_changed(value)


    def __setitem__(self, k, v):
        self._changed = True
        _try_set_changed(v)
        dict.__setitem__(self, k, v)


    def __delitem__(self, k):
        self._changed = True
        self._removed.add(k)
        dict.__delitem__(self, k)


    def _setitem(self, k, v):
        dict.__setitem__(self, k, v)


    def clear(self):
        self._changed = True
        self._removed.update(self.iterkeys())
        return dict.clear(self)


    def pop(self, key, *args, **kwargs):
        self._changed = True
        self._removed.add(key)
        return dict.pop(self, key, *args, **kwargs)


    def popitem(self):
        self._changed = True
        key, value = dict.popitem(self)
        self._removed.add(key)
        return (key, value)


    def setdefault(self, key, default=None):
        self._changed = True
        if default is None:
            default = self.value_field.value_type()
        return dict.setdefault(self, key, default)


    def update(self, *arg, **kwargs):
        self._changed = True
        self.broadcast_changed()
        return dict.update(self, *arg, **kwargs)


    cdef broadcast_changed(self):
        for v in self.itervalues():
            _try_set_changed(v)


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
    cdef int index
    cdef str name
    cdef str key

    cdef str type_name
    cdef object typ

    cdef object base_value_type
    cdef DataModelProtocol data_model_protocol

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

    cdef dict __dict__


    property index:
        def __get__(self):
            return self.index


    property name:
        def __get__(self):
            return self.name


    property key:
        def __get__(self):
            return self.key

    cdef inline bint is_data_model_type(self):
        return self.data_model_protocol is not None

    def __cinit__(self, object typ, int index, bint array=False, bint map=False, bint id_map=False,
                  str key=None, object default=None, object min_value=None, bint arithm=False,
                  bint ref=False, **kwargs):

        self.__dict__ = {}
        self.typ = typ
        if isinstance(typ, (str, unicode)) and typ in _default_values:
            self.type_name = typ
            self.base_value_type = typ
        elif issubclass(typ, DataModel):
            self.type_name = typ.__name__
            self.data_model_protocol = <DataModelProtocol>typ._protocol_
        else:
            raise DefineError('unsupported type')

        self.index = index
        if index <= 0 or index > 2 ** 16:
            raise DefineError('invalid index')

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

        self.is_unsigned = True if self.type_name in _unsigned_int_types else False
        self.ref = ref

        if self.ref:
            if not self.is_data_model_type():
                raise TypeError("ref must pointer to a DataModel type")

        self.skip_changed = False
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
            value_field = self.data_model_protocol.fields_define.fields_by_name['oid']
            self.dict_ref_encoder = value_field.dict_encoder
            self.dict_ref_decoder = value_field.dict_decoder

        #if self.ref:
        #    value_field = self.data_model_value_type._fields_by_name['oid']

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


    cdef inline bint is_container(self):
        return self.container_class is not None

    def __str__(self):
        return '<%s name=%s, index=%d>' % (self.__class__.__name__, self.name, self.index)

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


cdef DataModelProtocol try_get_protocol(object cls_or_obj):
    cdef object pto = getattr(cls_or_obj, '_protocol_', None)
    if pto is None:
        return None
    if not isinstance(pto, DataModelProtocol):
        return None
    return pto


cdef class FieldsDefine:
    cdef list fields
    cdef dict fields_by_index
    cdef dict fields_by_name
    cdef dict fields_by_key
    cdef dict fields_is_container

    def __init__(self):
        self.fields = []
        self.fields_by_index = {}
        self.fields_by_name = {}
        self.fields_by_key = {}
        self.fields_is_container = {}

    def add_field(self, Field field):
        self.fields.append(field)
        self.sort_fields()
        self.fields_by_index[field.index] = field
        self.fields_by_name[field.name] = field
        self.fields_by_key[field.key] = field

    def copy_bases_fields(self, bases):
        cdef DataModelProtocol protocol
        for base in bases:
            protocol = try_get_protocol(base)
            if protocol is not None:
                self.copy_class_fields(protocol.fields_define)
                self.copy_bases_fields(base.__bases__)


    def sort_fields(self):
        self.fields.sort(lambda a, b: cmp(a.index, b.index))

    def copy_class_fields(self, FieldsDefine other):
        '''
        cdef Field self_field
        cdef Field cls_field

        # 确保index和name不重复
        cdef int index
        for index in fdef.fields_by_index:
            if index in self.fields_by_index:
                self_field = self.fields_by_index[index]
                cls_field = fdef.fields_by_index[index]
                if self_field.class_name != cls.__name__:
                    if self_field.define_in_class is not cls_field.define_in_class:
                        raise DuplicateIndexError(
                            "duplicate field index `%d' between class %s, %s"
                            % (index, self_field.class_name, cls.__name__))
        for name in cls.fields_by_name:
            if name in self.fields_by_name:
                self_field = self.fields_by_name[name]
                cls_field = cls.fields_by_name[name]
                if self_field.class_name != cls.__name__:
                    if self_field.define_in_class is not cls_field.define_in_class:
                        raise DuplicateNameError(
                            "duplicate field name `%s' between class %s, %s" %
                            (name, self_field.class_name, cls.__name__))
        '''

        self.fields += other.fields[:]
        self.sort_fields()
        self.fields_by_index.update(other.fields_by_index)
        self.fields_by_name.update(other.fields_by_name)
        self.fields_by_key.update(other.fields_by_key)
        self.fields_is_container.update(other.fields_is_container)


cdef object make_get_func(Field field):
    if field.is_data_model_type():
        def get_func(self):
            cdef dict d = self.__dict__
            if field.key not in d:
                d[field.key] = field.data_model_value_type()
            return d[field.key]
        return get_func
    else:
        def get_func(self):
            return self.__dict__.setdefault(field.key, field.default)
        return get_func


cdef object make_add_func(Field field):
    if field.type_name in _int_types:
        if field.type_name in _unsigned_int_types:
            def _add(object self, uint64 value):
                cdef dict d = self.__dict__
                cdef uint64 old_value = d.get(field.key, 0)
                cdef uint64 new_value = old_value + value
                d[field.key] = new_value
                return value, new_value
            return _add
        else:
            def _add(object self, int64 value):
                cdef dict d = self.__dict__
                cdef int64 old_value = d.get(field.key, 0)
                cdef int64 new_value = old_value + value
                d[field.key] = new_value
                return value, new_value
            return _add
    else:
        raise TypeError("not a integer type")


cdef object make_sub_func_with_min_value(Field field, object _min_value=None):
    cdef int64 i_min_value = 0
    cdef uint64 ui_min_value = 0
    if field.type_name in _int_types:
        if field.type_name in _unsigned_int_types:
            if _min_value is not None:
                ui_min_value = _min_value
            def _sub(object self, object value):
                cdef dict d = self.__dict__
                cdef uint64 old_value = d.get(field.key, 0)
                cdef uint64 new_value = old_value - value
                if new_value < ui_min_value:
                    raise ValueError('overflow lower limit')
                d[field.key] = new_value
                return old_value - new_value, new_value
            return _sub
        else:
            if _min_value is not None:
                i_min_value = _min_value
            def _sub(object self, object value):
                cdef dict d = self.__dict__
                cdef int64 old_value = d.get(field.key, 0)
                cdef int64 new_value = old_value - value
                if new_value < i_min_value:
                    raise ValueError('overflow lower limit')
                d[field.key] = new_value
                return old_value - new_value, new_value
            return _sub
    else:
        raise TypeError("not a integer type")


cdef object make_unsigned_sub_func(Field field):
    return make_sub_func_with_min_value(field, 0)


cdef object make_signed_sub_func(Field field):
    def _sub(object self, object _value):
        cdef dict d = self.__dict__
        cdef int64 old_value = d.get(field.key, 0)
        cdef int64 value = _value
        cdef int64 new_value = old_value - value
        d[field.key] = new_value
        return value, new_value
    return _sub


cdef object make_container_fget(Field field):
    def fget(object self):
        return self.__dict__.setdefault(field.key, field.container_class())
    return fget


cdef object make_container_fset(Field field):
    def fset(object self, object value):
        if isinstance(value, field.container_class):
            _broadcast_changed(value)
            self.__dict__[field.key] = value
        else:
            value = field.container_class(value)
            _broadcast_changed(value)
            self.__dict__[field.key] = value
        _mark_changed(field.index, self)
    return fset


cdef object make_container_fdel(Field field):
    def fdel(object self):
        raise OperateError('cannot del a container field')
    return fdel

cdef object make_container_get_func(Field field):
    def get(object self):
        cdef dict d = self.__dict__
        if field.key not in d:
            d[field.key] = field.container_class()
        return d[field.key]
    return get


cdef class DataModelProtocol:
    cdef FieldsDefine fields_define
    cdef object cls
    cdef str cls_name



cdef class MetaDataModel(type):
    def __init__(cls, clsname, bases, attrs):
        if bases is None:
            return
        cdef DataModelProtocol protocol = DataModelProtocol()
        protocol.cls = cls
        protocol.cls_name = clsname
        cls._protocol_ = protocol

        cdef FieldsDefine fields_define = FieldsDefine()
        protocol.fields_define = fields_define

        fields_define.copy_bases_fields(bases)

        cdef Field field
        cdef str key

        for name, _field in attrs.iteritems():
            if name.startswith('__'):
                continue
            if not isinstance(_field, Field):
                continue

            field = _field

            field.data_model_protocol = protocol

            key = '_' + name
            field.name = name
            field.key = key

            cls.make_auto_gen_methods(field, attrs)

            fields_define.add_field(field)


    def make_auto_gen_methods(cls, Field field, attrs):
        cdef str get_func_name
        if field.is_container():
            setattr(cls, field.name, property(
                make_container_fget(field),
                make_container_fset(field),
                make_container_fdel(field)))
            get_func_name = make_autogen_func_name(attrs, 'get', field.name)
            setattr(cls, get_func_name,
                PyMethod_New(make_container_get_func(field), None, cls))
        else:
            setattr(cls, field.name, property(
                make_fget(field),
                make_fset(field),
                make_fdel(field)))
            get_func_name = make_autogen_func_name(attrs, 'get', field.name)
            setattr(cls, get_func_name,
                PyMethod_New(make_get_func(field), None, cls))

        if field.arithm:
            # 生成 add_`name' or _add_`name' 函数
            add_func_name = make_autogen_func_name(attrs, 'add', field.name)
            setattr(cls, add_func_name,
                PyMethod_New(make_add_func(field), None, cls))

            # 生成 sub_`name' or _sub_`name' 函数
            sub_func_name = make_autogen_func_name(attrs, 'sub', field.name)
            if field.has_min_value:
                setattr(cls, sub_func_name,
                    PyMethod_New(make_sub_func_with_min_value(field), None, cls))
            elif field.is_unsigned:
                setattr(cls, sub_func_name,
                    PyMethod_New(make_unsigned_sub_func(field), None, cls))
            else:
                setattr(cls, sub_func_name,
                    PyMethod_New(make_signed_sub_func(field), None, cls))


cdef class DataModel(object):

    cdef DataModelProtocol protocol
    cdef FieldDirtySet changed_set


    def __getmetaclass__(_):
        return MetaDataModel


    def __cinit__(self):
        self.protocol = self._protocol_


    cpdef DataModelProtocol _get_protocol(self):
        return self.protocol


    cpdef FieldsDefine _get_fields_define(self):
        return self.protocol.fields_define


    def __init__(self, **kwargs):
        self._set_data(kwargs)


    def set_data(self, **kwargs):
        self._set_data(kwargs)


    cdef void _set_data(self, kwargs):
        if not kwargs:
            return
        cdef FieldsDefine fields_define = self._get_fields_define()
        obj_dict = self.__dict__
        cdef dict fields_by_name = fields_define.fields_by_name
        cdef Field field
        for name, value in kwargs.iteritems():
            field = fields_by_name.get(name)
            if field is not None:
                obj_dict[field.key] = value
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


    cdef void _clear_field_changed(self, dict self_dict, Field field,
                                   bint recursive,
                                   bint clear_self_changed_set=True):
        if not field.key in self_dict:
            return
        if clear_self_changed_set:
            self.changed_set.clear_dirty(field.index)
        if recursive:
            value = self_dict.get(field.key)
            if field.is_container():
                _container_clear_changed(field, value, recursive)
            elif field.is_data_model_type():
                dm_value = <DataModel>value
                dm_value._clear_changed(None, recursive)


    cdef void _clear_changed(self, object field_names, bint recursive):
        cdef Field field
        cdef dict self_dict
        cdef object value
        cdef DataModel dm_value
        cdef str field_name
        cdef int field_index

        if field_names is None:
            self.changed_set.clear_all()
            if recursive:
                self_dict = self.__dict__
                for field in self.protocol.fields_define.fields:
                    self._clear_field_changed(self_dict, field, recursive, False)
        else:
            self_dict = self.__dict__
            for field_name in field_names:
                field = self.protocol.fields_define.fields_by_name.get(field_name)
                self._clear_field_changed(self_dict, field, recursive, True)


    def clear_changed(self, *field_names, **options):
        cdef bint recursive
        _recursive = options.get('recursive')
        if _recursive is None:
            recursive = True
        elif _recursive:
            recursive = True
        else:
            recursive = False
        return self._clear_changed(field_names, recursive)


    cdef void _mark_field_changed(self, Field field):
        self.changed_set.set_dirty(field.index, True)


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
                     only_changed=False, clear_changed=False, field_filter=None):
        cdef dict dict_data = {}
        cdef DataModelProtocol protocol = self._get_protocol()
        _encode_to_dict(dict_data, protocol, self,
                        recursive=recursive,
                        only_changed=only_changed,
                        clear_changed=clear_changed,
                        field_filter=field_filter)
        return dict_data


    def unpack_from_dict(self, dict src_dict_data, str mode=None, object resolve_ref=None, bint mark_change=False):
        cdef DecodeContext context = DecodeContext(mode=mode, resolve_ref=resolve_ref, mark_change=mark_change)
        cdef DataModelProtocol protocol = self._get_protocol()
        _decode_from_dict(protocol, self, self.__dict__, src_dict_data, context)
        context.resolve_ref()
        return context.unsolved_ref


    def get_changed_dict(self, recursive=False):
        return self.pack_to_dict(recursive, only_changed=True)


    def pack(self, fmt, *args, **kwargs):
        if fmt == 'dict':
            return self.pack_to_dict(*args, **kwargs)
        else:
            raise PackError('unsupported format: {}'.format(fmt))


    def unpack(self, fmt, *args, **kwargs):
        if fmt == 'dict':
            return self.unpack_from_dict(*args, **kwargs)
        else:
            raise PackError('unsupported format: {}'.format(fmt))


    def __str__(self):
        return self._long_repr_()


    def __repr__(self):
        return self._long_repr_()


    cdef str _get_info_(self, int nfields):
        cdef list array = []
        cdef int idx = 0
        cdef FieldsDefine fields_define = self._get_fields_define()
        cdef Field field
        cdef str key
        while nfields > 0 and idx < len(fields_define.fields):
            field = fields_define.fields[idx]
            idx += 1
            if field.is_container():
                continue
            value = getattr(self, field.key, None)
            if value is not None:
                key = field.name
                info = '%s=%s' % (key, _value_short_repr(value))
                array.append(info)
                nfields -= 1
        cdef str obj_info = '%s(%s)' % (self.__class__.__name__, ','.join(array))
        return obj_info


    cdef str _short_repr_(self):
        return self._get_info_(2)


    cdef str _long_repr_(self):
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

