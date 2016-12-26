#pragma once

#include <set>
#include <bitset>

typedef unsigned short FieldIdx;
const int BASE_FIELDS_COUNT = 128;

class FieldDirtySet {
private:
    typedef std::set<FieldIdx> FieldSet;
private:
    std::bitset<BASE_FIELDS_COUNT> base_fields;
    FieldSet extra_fields;
    int dirty_count;
public:
    FieldDirtySet(): dirty_count(0) {}

    bool is_field_dirty(FieldIdx f) {
        if (f < BASE_FIELDS_COUNT) {
            return base_fields[f];
        } else {
            return extra_fields.find(f) != extra_fields.end();
        }
    }

    bool has_any_dirty() {
        return dirty_count > 0;
    }

    bool _set_field_dirty(FieldIdx f, bool value) {
        if (f < BASE_FIELDS_COUNT) {
            if (base_fields[f] != value) {
                base_fields[f] = value;
                return true;
            }
        } else {
            bool cur_value = (extra_fields.find(f) != extra_fields.end());
            if (cur_value != value) {
                if (value) {
                    extra_fields.insert(f);
                } else {
                    extra_fields.erase(f);
                }
                return true;
            }
        }
        return false;
    }

    void set_field_dirty(FieldIdx f) {
        if (_set_field_dirty(f, true)) {
            dirty_count ++;
        }
    }

    void clear_field_dirty(FieldIdx f) {
        if (_set_field_dirty(f, false)) {
            dirty_count --;
        }
	}

    void clear_all_dirty() {
        base_fields.reset();
        extra_fields.clear();
        dirty_count = 0;
    }

};
