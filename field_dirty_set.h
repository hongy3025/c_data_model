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
public:
    bool is_dirty(FieldIdx f) {
        if (f < BASE_FIELDS_COUNT) {
            return base_fields[f];
        } else {
            return extra_fields.find(f) != extra_fields.end();
        }
    }
    void set_dirty(FieldIdx f, bool value) {
        if (f < BASE_FIELDS_COUNT) {
            base_fields[f] = value;
        } else {
            extra_fields.insert(f);
        }
    }
    void clear_dirty(FieldIdx f) {
		set_dirty(f, false);
	}
    void clear_all() {
        base_fields.reset();
        extra_fields.clear();
    }
};
