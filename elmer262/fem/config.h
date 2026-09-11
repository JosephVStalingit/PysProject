#ifndef CONFIG_H_FEM
#define CONFIG_H_FEM
#ifdef USE_ISO_C_BINDINGS
#define FC_FUNC(name, NAME) name
#define FC_FUNC_(name, NAME) name
#endif
#define ELMER_FEM_VERSION "26.2"
#define ELMER_FEM_COMPILATIONDATE "2026-09-10"
#define HAVE_INTTYPES_H
#define ELMER_SOLVER_HOME "C:/Program Files/Elmer 26.2.1-Release/share/elmersolver"
#define OFF_KIND selected_int_kind(9)
#define STDCALLBULL
#define HAVE_ARPACK
#define HAVE_BLAS
#define HAVE_DLCLOSE
#define HAVE_DLERROR
#define HAVE_DLOPEN
#define HAVE_QP
#define HAVE_LOADLIBRARY_API
#define HAVE_FSEEKO
#define HAVE_FTELLO
#define HAVE_F_ETIME
#define HAVE_F_FLUSH
#define HAVE_HUTI
#define HAVE_LAPACK
#define HAVE_LIBDL
#define HAVE_MATC
#define HAVE_MPI
#if defined(HAVE_OPENMP45)
#define _ELMER_OMP $OMP
#define _ELMER_OMP_SIMD $OMP SIMD
#define _ELMER_OMP_DECLARE_SIMD $OMP DECLARE SIMD
#define _ELMER_LINEAR_REF(var) LINEAR(REF(var))
#elif defined(HAVE_OPENMP40)
#define _ELMER_OMP $OMP
#define _ELMER_OMP_SIMD $OMP SIMD
#define _ELMER_OMP_DECLARE_SIMD $OMP DECLARE SIMD
#define _ELMER_LINEAR_REF(var) 
#else
#define _ELMER_OMP
#define _ELMER_OMP_SIMD DIR$ IVDEP !
#define _ELMER_OMP_DECLARE_SIMD
#define _ELMER_LINEAR_REF(var) 
#endif
#define HAVE_PARPACK
#define HAVE_STDINT_H
#define HAVE_STDLIB_H
#define HAVE_STRINGS_H
#define HAVE_STRING_H
#define HAVE_SYS_STAT_H
#define HAVE_SYS_TYPES_H
#define HAVE_UMFPACK
#define UMFPACK_LONG_FORTRAN_TYPE C_LONG
#define HAVE_UNISTD_H
#define LINUX
#define SHL_EXTENSION ".dll"
#if 1
#endif
#define ELMER_LINKTYP 1
#define ENABLE_DYNAMIC_LINKING 1
#define DEVEL_LISTUSAGE
#endif
