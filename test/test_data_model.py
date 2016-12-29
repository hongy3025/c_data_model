# encoding=utf-8

import sys
sys.path.insert(0, '.')

import os

import pytest
import pprint

from traceback import print_exc

from c_data_model import *

class Point(DataModel):
    x = Field('int32', 1, arithm=True, min_value=-1, conf_name='xx')
    y = Field('uint32', 2, arithm=True, conf_name='yy')


class Point2(DataModel):
    x = Field('int32', 1, arithm=True, min_value=-1, conf_name='xx')
    y = Field('uint32', 2, arithm=True, conf_name='yy')


class Rect(DataModel):
    lt = Field(Point, 1)
    rb = Field(Point, 2)

class Box(DataModel):
    points = ArrayField(Point, 1)


class KeyPoints(DataModel):
    points = MapField(Point, 1, key='string')

class Coord(DataModel):
    oid = Field('string', 1)
    x   = Field('int32', 2, default=100)
    y   = Field('int32', 3, default=100)

class Scene(DataModel):
    coords  = MapField(Coord, 1, key='string')
    refs    = MapField(Coord, 2, key='string', ref=True)

class Scene2(DataModel):
    coords  = MapField(Coord, 1, key='string')
    refs    = MapField(Coord, 2, key='string', ref=True)
    point1  = Field(Point, 3)
    point2  = Field(Point, 4)

    def resolve_ref(self, ref):
        return self.coords.get(ref)

class Object(DataModel):
    oid  = Field('uint32', 1)
    name = Field('string', 2)

    def get_name(self):
        return 'my_get_name'

class Objects(DataModel):
    objects = IdMapField(Object, 1, key='uint32')


# def test_array():
#     b = Box()
#     print 'b.points', type(b.points)
#     assert(isinstance(b.points, Array))
# 
#     b.points = [Point(x=i, y=i) for i in xrange(4)]
#     assert(isinstance(b.points, Array))
#     print 'typeof b.points', type(b.points)
# 
#     print 'has_changed 1 ', b.has_changed()
#     assert(b.has_changed())
# 
#     out1 = b.pack_to_dict()
#     for i in xrange(4):
#         assert(out1['points'][i] == {'x': i, 'y': i})
#     print 'out1', out1
# 
#     b3 = Box()
#     b3.unpack_from_dict(out1)
#     print 'typeof b3.points', type(b3.points)
#     assert(isinstance(b3.points, Array))
# 
#     b.clear_changed()
#     print 'has_changed 2 ', b.has_changed()
#     assert(not b.has_changed())
# 
#     b.points[0] = Point(x=40, y=40)
#     print 'has_changed 4 ', b.has_changed()
#     assert(b.has_changed())
# 
#     b.clear_changed()
#     b.points += [Point(x=50, y=50)]
#     print 'has_changed 5 ', b.has_changed()
#     assert(b.has_changed())
# 
#     b.clear_changed()
#     b.points.append(Point(x=60, y=60))
#     print 'has_changed 6 ', b.has_changed()
#     assert(b.has_changed())
# 
#     b.clear_changed()
#     b.points.insert(0, Point(x=70, y=70))
#     print 'has_changed 7 ', b.has_changed()
#     assert(b.has_changed())
# 
#     b.clear_changed()
#     b.points.pop(2)
#     print 'has_changed 8 ', b.has_changed()
#     assert(b.has_changed())
# 
#     print 'del b.points'
#     with pytest.raises(OperateError):
#         del b.points
# 
#     out2 = b.pack_to_dict()
#     print 'out2', out2
#     assert(out2 == {'points': [{'y': 70, 'x': 70}, {'y': 40, 'x': 40}, {'y': 2, 'x': 2}, {'y': 3, 'x': 3}, {'y': 50, 'x': 50}, {'y': 60, 'x': 60}]})
# 
#     b.clear_changed()
#     b.points.sort(lambda a, b: cmp(a.x, b.x))
#     print 'has_changed 9 ', b.has_changed()
#     assert(b.has_changed())
# 
#     out2 = b.pack_to_dict()
#     print 'out2', out2
#     assert(out2 == {'points': [{'y': 2, 'x': 2}, {'y': 3, 'x': 3}, {'y': 40, 'x': 40}, {'y': 50, 'x': 50}, {'y': 60, 'x': 60}, {'y': 70, 'x': 70}]})
# 
#     b2 = Box()
#     b2.points = [Point(x=1001)]
#     assert(b2.points[0].x == 1001)
#     print 'b2.points[0].x', b2.points[0].x
# 
def test_changed():
    p = Point(x=1)
    p.y = 2
    assert p.has_changed('y')
    out = p.pack_to_dict(only_changed=True)
    print 'out 1', out
    assert out == {'y': 2}

    p.clear_changed()

    assert not p.has_changed('x')
    assert not p.has_changed('y')
    assert not p.has_changed()

    p.set_changed('x', 'y')

    assert p.has_changed('x')
    assert p.has_changed('y')
    assert p.has_changed()

    p.clear_changed('y')
    out = p.pack_to_dict(only_changed=True)
    print 'out 2', out
    assert out == {'x': 1}

    p.clear_changed()

    p.set_changed()

    assert p.has_changed('x')
    assert p.has_changed('y')
    assert p.has_changed()

    p.clear_changed()
    out = p.pack_to_dict(only_changed=True)
    print 'out 3', out
    assert out == {}

# 
# def test_changed_2():
#     rect = Rect(lt=Point(x=1, y=1), rb=Point(x=2, y=2))
#     rect.lt.x = 100
#     rect.rb.y = 100
#     out = rect.pack('dict', only_changed=True)
#     print 'changed_dict 6', out
# 
# def test_duplicate_index():
#     with pytest.raises(DuplicateIndexError):
#         class Point3d(Point):
#             x_ = Field('int32', 1)
#             y_ = Field('int32', 2)
#             z_ = Field('int32', 3)
# 
# def test_duplicate_name():
#     with pytest.raises(DuplicateNameError):
#         class Point3d2(Point):
#             x = Field('int32', 4)
#             y = Field('int32', 5)
#             z = Field('int32', 6)
# 
# def test_map():
#     kp = KeyPoints()
#     assert(isinstance(kp.points, Map))
#     kp.points['a'] = Point(x=1, y=2)
#     assert(kp.points['a'].x == 1)
#     out1 = kp.pack_to_dict()
#     print 'out1', out1
#     assert(out1 == {'points': {'a': {'y': 2, 'x': 1}}})
# 
#     kp2 = KeyPoints()
#     kp2.unpack_from_dict(out1)
#     assert(isinstance(kp2.points, Map))
#     assert(kp2.points['a'].x == 1)
#     out2 = kp2.pack_to_dict()
#     print 'out2', out2
#     assert(out2 == {'points': {'a': {'y': 2, 'x': 1}}})
# 
# def test_bin():
#     p = Point(x=1, y=2)
#     s1 = p.pack_to_binary()
#     print 's1', repr(s1), len(s1)
# 
#     b = Box()
#     b.points = [Point(x=i, y=i) for i in xrange(4)]
#     s2 = b.pack_to_binary()
#     print 's2', repr(s2), len(s2)
# 
# def test_changed_3():
#     kp = KeyPoints()
#     kp.points['a'] = Point(x=1, y=2)
#     out = kp.pack('dict', only_changed=True)
#     print 'out 1:'
#     pprint.pprint(out, indent=2)
#     assert(out == {'points': { 'a': { 'x': 1, 'y': 2}}})
# 
#     kp.clear_changed()
# 
#     kp.points['b'] = Point(x=3, y=4)
#     out = kp.pack('dict', only_changed=True)
#     print 'out 2:'
#     pprint.pprint(out, indent=2)
#     assert(out == {'points': { 'b': { 'x': 3, 'y': 4}}})
# 
#     kp.clear_changed()
# 
#     kp.points['c'] = Point(x=5, y=6)
#     out = kp.pack('dict', only_changed=True, clear_changed=True)
#     print 'out 3:'
#     pprint.pprint(out, indent=2)
#     assert(out == { 'points': {'c': { 'x': 5, 'y': 6}}})
# 
#     out = kp.pack('dict', only_changed=True)
#     print 'out 4:', kp.has_changed()
#     pprint.pprint(out, indent=2)
#     assert(out == {})
# 
# def test_ref():
#     s = Scene()
# 
#     s.coords['a'] = Coord(oid='a', x=1, y=2)
#     s.coords['b'] = Coord(oid='b', x=3, y=4)
#     s.coords['c'] = Coord(oid='c', x=5, y=6)
#     s.refs['1'] = s.coords['a']
#     s.refs['2'] = s.coords['b']
#     s.clear_changed()
# 
#     print 'out1:'
#     out = s.pack('dict')
#     pprint.pprint(out, indent=2)
# 
# def test_ref_2():
#     s = Scene2()
# 
#     s.coords['a'] = Coord(oid='a', x=1, y=2)
#     s.coords['b'] = Coord(oid='b', x=3, y=4)
#     s.coords['c'] = Coord(oid='c', x=5, y=6)
#     s.refs['1'] = s.coords['a']
#     s.refs['2'] = s.coords['b']
#     s.clear_changed()
# 
#     s_out = s.pack('dict')
#     print 's:'
#     pprint.pprint(s_out, indent=2)
# 
#     d = Scene2()
#     d.unpack('dict', s_out)
#     d_out = d.pack('dict')
#     print 'd:'
#     pprint.pprint(d_out, indent=2)
# 
#     assert(s_out == d_out)
# 
#     #------------------------------------------------------------------
# 
#     s.refs['3'] = s.coords['c']
#     s_changed = s.pack('dict', only_changed=True)
#     print 's_changed:'
#     pprint.pprint(s_changed, indent=2)
# 
#     unsolved = d.unpack('dict', s_changed, mode='sync', resolve_ref=lambda ref: d.resolve_ref(ref))
#     assert(not unsolved) # 确保所有引用都已经解析
# 
#     d_out = d.pack('dict')
#     print 'd 2:'
#     pprint.pprint(d_out, indent=2)
#     assert(d_out == s.pack('dict'))
# 
#     s.clear_changed()
# 
#     s.point1 = Point(x=1, y=2)
#     print 's 2:'
#     diff = s.pack('dict', only_changed=True)
#     pprint.pprint(diff, indent=2)
# 
#     s.clear_changed()
# 
#     s.coords['e'] = Coord(oid='e', x=11, y=12)
#     print 's 3:'
#     diff = s.pack('dict', only_changed=True)
#     pprint.pprint(diff, indent=2)
# 
#     s.clear_changed()
# 
#     print 's has_changed:', s.has_changed()
#     assert(not s.has_changed())
# 
#     print 's 4:'
#     diff = s.pack('dict', only_changed=True)
#     pprint.pprint(diff, indent=2)
#     assert(diff == {})
# 
# def test_id_map():
#     objects = Objects()
#     objects.objects.add(Object(oid=1, name='name1'))
#     objects.objects.add(Object(oid=2, name='name2'))
#     print 'out 1:'
#     out = objects.pack('dict')
#     pprint.pprint(out, indent=2)
# 
#     # id_map不序列化oid字段。自动将整数key序列化为字符串类型。
#     assert(out == { 'objects': { '1': { 'name': 'name1'}, '2': { 'name': 'name2'}}})
# 
#     objects_2 = Objects()
#     objects_2.unpack('dict', out)
#     # 反序列化后，对象内自动赋值oid字段。自动还原整数类型的key。
#     assert(objects_2.objects[1].oid == 1)
# 
# def test_inherit():
#     class PointX(DataModel):
#         x = Field('int32', 1)
# 
#     class PointY(PointX):
#         pass
# 
#     class PointZ(PointY):
#         pass
# 
#     class PointA(PointZ):
#         pass
# 
#     point = PointA(x=1)
#     print 'out1', point.x
#     assert(point.x == 1)
# 
# def test_auto_name():
#     obj = Object()
#     obj.name = 'the_name'
#     assert obj.get_name() == 'my_get_name'
#     obj._get_name()
#     assert obj._get_name() == 'the_name'
# 
# def test_auto_func():
#     pt = Point()
#     pt.x = 1
#     result = pt.add_x(3)
#     print 'result 1', result
#     assert result[0] == 3
#     assert result[1] == 4
#     result = pt.sub_x(1)
#     print 'result 2', result
#     assert result[0] == 1
#     assert result[1] == 3
#     pt.y = 3
#     result = pt.sub_y(3)
#     print 'result 3', result
#     assert result[0] == 3
#     assert result[1] == 0
#     # result = pt.sub_y(1)
#     # result = pt.sub_x(100)
# 
# 
# def test_field_custom_param():
#     for field in Point._fields:
#         print 'field', field.conf_name
# 
# def test_default_value():
#     coord = Coord()
#     print 'coord.x', coord.x
#     assert coord.x == 100
#

def test_base_1():
    p = Point(x=1, y=2)
    print 'p.x', p.x
    print p
    out1 = p.pack_to_dict()
    print 'out1', out1
    p2 = Point()
    p2.unpack_from_dict(out1, mark_change=True)
    print 'p2', p2


def test_base_usage():
    rect = Rect()
    rect.lt = Point(x=1, y=1)
    rect.rb = Point(x=100, y=101)
    rect.lt.x = 20

    assert rect.lt.x == 20
    assert rect.lt.y == 1
    assert rect.rb.x == 100
    assert rect.rb.y == 101

    out1 = rect.pack_to_dict()
    assert out1 == {'lt': {'y': 1, 'x': 20}, 'rb': {'x': 100, 'y': 101}}

    rect2 = Rect()
    rect2.unpack_from_dict(out1)

    print 'rect2.lt', rect2.lt.x, rect2.lt.y
    print 'rect2.rb', rect2.rb.x, rect2.rb.y

    assert rect2.lt.x == 20
    assert rect2.lt.y == 1
    assert rect2.rb.x == 100
    assert rect2.rb.y == 101


def main():
    try:
        # test_base_1()
        # test_base_usage()
        test_changed()
        # test_changed_2()
        # test_array()
        # test_map()
        # test_bin()
        # test_changed_3()
        # test_ref()
        # test_ref_2()
        # test_id_map()
        # test_inherit()
        # test_auto_name()
        # test_auto_func()
        # test_field_custom_param()
        # test_default_value()
    except:
        print_exc()

if __name__ == '__main__':
    main()

