# coding=utf-8

# pylint: disable=wildcard-import

#
# 是否使用 c_data_model: auto: 自动选择 on 强制使用 off 不使用
#
CONFIG_USING_C_DATA_MODEL = 'auto'


# --------------------------------------------------------------------

if CONFIG_USING_C_DATA_MODEL == 'on':
    using_c_data_model = True
elif CONFIG_USING_C_DATA_MODEL == 'auto':
    try:
        import c_data_model
        using_c_data_model = True
    except:
        using_c_data_model = False
else:
    using_c_data_model = False

if using_c_data_model:
    from c_data_model import *
else:
    from .data_model import *
