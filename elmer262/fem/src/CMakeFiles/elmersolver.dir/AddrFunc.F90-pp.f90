# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/AddrFunc.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/AddrFunc.F90"
! Function for obtaining addresses to a Fortran subroutines or functions

FUNCTION AddrFunc(fn) RESULT(faddr)
    USE ISO_C_BINDING
    USE Types, ONLY : AddrInt
    IMPLICIT NONE
    INTERFACE
        SUBROUTINE dummysubr() bind(C)
        END SUBROUTINE
    END INTERFACE
    PROCEDURE(dummysubr) :: fn  
    INTEGER(KIND=AddrInt) :: faddr

    TYPE(C_FUNPTR) :: cptr
    cptr = C_FUNLOC(fn)
    faddr = TRANSFER(cptr, faddr)
END FUNCTION AddrFunc
