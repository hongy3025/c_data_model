from distutils.command.build_ext import build_ext
from distutils.core import setup
from distutils.extension import Extension

from Cython.Build import cythonize

extra_compile_args = {
    'msvc': ['/EHsc', '/wd4146'],
    'gcc': ['-Wno-unused-function', '-Wno-unneeded-internal-declaration'],
}

extra_libraries = {
    'gcc': [],
}

ext_modules = cythonize([
    Extension(
        'c_data_model',
        sources=['c_data_model.pyx'],
        language='c++',
    ),
])

class BuildExtSubclass(build_ext):
    def build_extensions(self):
        c = self.compiler.compiler_type
        extra_copts = extra_compile_args.get(c)
        if extra_copts is None:
            extra_copts = extra_compile_args.get('gcc')
        extra_libs = extra_libraries.get(c)
        if extra_libs is None:
            extra_libs = extra_libraries.get('gcc')
        for e in self.extensions:
            e.extra_compile_args += extra_copts
            e.libraries += extra_libs
        build_ext.build_extensions(self)

setup(version='0.1',
      name='c_data_model',
      ext_modules=ext_modules,
      packages=[],
      author='HongYing',
      author_email='hongy3025@163.com',
      cmdclass={'build_ext': BuildExtSubclass},
      description='c_data_model')
