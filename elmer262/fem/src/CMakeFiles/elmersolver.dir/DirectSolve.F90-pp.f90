# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
!
! *
! *  Elmer, A Finite Element Software for Multiphysical Problems
! *
! *  Copyright 1st April 1995 - , CSC - IT Center for Science Ltd., Finland
! * 
! *  This library is free software; you can redistribute it and/or
! *  modify it under the terms of the GNU Lesser General Public
! *  License as published by the Free Software Foundation; either
! *  version 2.1 of the License, or (at your option) any later version.
! *
! *  This library is distributed in the hope that it will be useful,
! *  but WITHOUT ANY WARRANTY; without even the implied warranty of
! *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
! *  Lesser General Public License for more details.
! * 
! *  You should have received a copy of the GNU Lesser General Public
! *  License along with this library (in file ../LGPL-2.1); if not, write 
! *  to the Free Software Foundation, Inc., 51 Franklin Street, 
! *  Fifth Floor, Boston, MA  02110-1301  USA
! *
! *****************************************************************************/
!
!
# 36 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"

!> \ingroup ElmerLib 
!> \{

!------------------------------------------------------------------------------
!>  Module containing the direct solvers for linear systems given in CRS format.
!> Included are Lapack band matrix solver, multifrontal Umfpack, MUMPS, SuperLU, 
!> and Pardiso. Note that many of these are linked in with ElmerSolver only 
!> if they are made available at the compilation time. 
!------------------------------------------------------------------------------


# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build/fem/config.h" 1
# 48 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90" 2

MODULE DirectSolve

   USE CRSMatrix
   USE BandMatrix
   USE SParIterSolve

   IMPLICIT NONE

CONTAINS


!------------------------------------------------------------------------------
!> Solver the complex linear system using direct band matrix solver from of Lapack.
!------------------------------------------------------------------------------
   SUBROUTINE ComplexBandSolver( A,x,b, Free_fact )
!------------------------------------------------------------------------------

     LOGICAL, OPTIONAL :: Free_Fact
     TYPE(Matrix_t) :: A
     REAL(KIND=dp) :: x(*),b(*)
!------------------------------------------------------------------------------

   
     INTEGER :: i,j,k,istat,Subband,N
     COMPLEX(KIND=dp), ALLOCATABLE :: BA(:,:)

     REAL(KIND=dp), POINTER  :: Values(:)
     INTEGER, POINTER  :: Rows(:), Cols(:), Diag(:)

     SAVE BA
!------------------------------------------------------------------------------

     IF ( PRESENT(Free_Fact) ) THEN
       IF ( Free_Fact ) THEN
         IF ( ALLOCATED(BA) ) DEALLOCATE(BA)
         RETURN
       END IF
     END IF

     Rows => A % Rows
     Cols => A % Cols
     Diag => A % Diag
     Values => A % Values

     n = A % NumberOfRows
     x(1:n) = b(1:n)
     n = n / 2

     IF ( A % Format == MATRIX_CRS .AND. .NOT. A % Symmetric ) THEN
       Subband = 0
       DO i=1,N
         DO j=Rows(2*i-1),Rows(2*i)-1,2
           Subband = MAX(Subband,ABS((Cols(j)+1)/2-i))
         END DO
       END DO

       IF ( .NOT.ALLOCATED( BA ) ) THEN

         ALLOCATE( BA(3*SubBand+1,N),stat=istat )

         IF ( istat /= 0 ) THEN
           CALL Fatal( 'ComplexBandSolver', 'Memory allocation error.' )
         END IF

       ELSE IF ( SIZE(BA,1) /= 3*Subband+1 .OR. SIZE(BA,2) /= N ) THEN

         DEALLOCATE( BA )
         ALLOCATE( BA(3*SubBand+1,N),stat=istat )

         IF ( istat /= 0 ) THEN
           CALL Fatal( 'ComplexBandSolver', 'Memory allocation error.' )
         END IF

       END IF

       BA = 0.0D0
       DO i=1,N
         DO j=Rows(2*i-1),Rows(2*i)-1,2
           k = i - (Cols(j)+1)/2 + 2*Subband + 1
           BA(k,(Cols(j)+1)/2) = CMPLX(Values(j), -Values(j+1), KIND=dp )
         END DO
       END DO

       CALL SolveComplexBandLapack( N,1,BA,x,Subband,3*Subband+1 )

     ELSE IF ( A % Format == MATRIX_CRS ) THEN

       Subband = 0
       DO i=1,N
         DO j=Rows(2*i-1),Diag(2*i-1)
           Subband = MAX(Subband,ABS((Cols(j)+1)/2-i))
         END DO
       END DO

       IF ( .NOT.ALLOCATED( BA ) ) THEN

         ALLOCATE( BA(SubBand+1,N),stat=istat )

         IF ( istat /= 0 ) THEN
           CALL Fatal( 'ComplexBandSolver', 'Memory allocation error.' )
         END IF

       ELSE IF ( SIZE(BA,1) /= Subband+1 .OR. SIZE(BA,2) /= N ) THEN

         DEALLOCATE( BA )
         ALLOCATE( BA(SubBand+1,N),stat=istat )

         IF ( istat /= 0 ) THEN
           CALL Fatal( 'ComplexBandSolver', 'Direct solver memory allocation error.' )
         END IF

       END IF

       BA = 0.0D0
       DO i=1,N
         DO j=Rows(2*i-1),Diag(2*i-1)
           k = i - (Cols(j)+1)/2 + 1
           BA(k,(Cols(j)+1)/2) = CMPLX(Values(j), -Values(j+1), KIND=dp )
         END DO
       END DO

       CALL SolveComplexSBandLapack( N,1,BA,x,Subband,Subband+1 )

     END IF
!------------------------------------------------------------------------------
  END SUBROUTINE ComplexBandSolver 
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Solver the real linear system using direct band matrix solver from of Lapack.
!------------------------------------------------------------------------------
   SUBROUTINE BandSolver( A,x,b,Free_Fact )
!------------------------------------------------------------------------------
     LOGICAL, OPTIONAL :: Free_Fact
     TYPE(Matrix_t) :: A
     REAL(KIND=dp) :: x(*),b(*)
!------------------------------------------------------------------------------

     INTEGER :: i,j,k,istat,Subband,N
     REAL(KIND=dp), ALLOCATABLE :: BA(:,:)

     REAL(KIND=dp), POINTER  :: Values(:)
     INTEGER, POINTER  :: Rows(:), Cols(:), Diag(:)

     SAVE BA
!------------------------------------------------------------------------------
     IF ( PRESENT(Free_Fact) ) THEN
       IF ( Free_Fact ) THEN
         IF ( ALLOCATED(BA) ) DEALLOCATE(BA)
         RETURN
       END IF
     END IF

     N = A % NumberOfRows

     x(1:n) = b(1:n)

     Rows => A % Rows
     Cols => A % Cols
     Diag => A % Diag
     Values => A % Values

     IF ( A % Format == MATRIX_CRS ) THEN ! .AND. .NOT. A % Symmetric ) THEN
        Subband = 0
        DO i=1,N
          DO j=Rows(i),Rows(i+1)-1
            Subband = MAX(Subband,ABS(Cols(j)-i))
          END DO
        END DO

        IF ( .NOT.ALLOCATED( BA ) ) THEN

          ALLOCATE( BA(3*SubBand+1,N),stat=istat )

          IF ( istat /= 0 ) THEN
            CALL Fatal( 'BandSolver', 'Memory allocation error.' )
          END IF

        ELSE IF ( SIZE(BA,1) /= 3*Subband+1 .OR. SIZE(BA,2) /= N ) THEN

          DEALLOCATE( BA )
          ALLOCATE( BA(3*SubBand+1,N),stat=istat )

          IF ( istat /= 0 ) THEN
            CALL Fatal( 'BandSolver', 'Memory allocation error.' )
          END IF

       END IF

       BA = 0.0D0
       DO i=1,N
         DO j=Rows(i),Rows(i+1)-1
           k = i - Cols(j) + 2*Subband + 1
           BA(k,Cols(j)) = Values(j)
         END DO
       END DO

       CALL SolveBandLapack( N,1,BA,x,Subband,3*Subband+1 )

     ELSE IF ( A % Format == MATRIX_CRS ) THEN

       Subband = 0
       DO i=1,N
         DO j=Rows(i),Diag(i)
           Subband = MAX(Subband,ABS(Cols(j)-i))
         END DO
       END DO

       IF ( .NOT.ALLOCATED( BA ) ) THEN

         ALLOCATE( BA(SubBand+1,N),stat=istat )

         IF ( istat /= 0 ) THEN
           CALL Fatal( 'BandSolver', 'Memory allocation error.' )
         END IF

       ELSE IF ( SIZE(BA,1) /= Subband+1 .OR. SIZE(BA,2) /= N ) THEN

         DEALLOCATE( BA )
         ALLOCATE( BA(SubBand+1,N),stat=istat )

         IF ( istat /= 0 ) THEN
           CALL Fatal( 'BandSolver', 'Memory allocation error.' )
         END IF

       END IF

       BA = 0.0D0
       DO i=1,N
         DO j=Rows(i),Diag(i)
           k = i - Cols(j) + 1
           BA(k,Cols(j)) = Values(j)
         END DO
       END DO

       CALL SolveSBandLapack( N,1,BA,x,Subband,Subband+1 )

     ELSE IF ( A % Format == MATRIX_BAND ) THEN
       CALL SolveBandLapack( N,1,Values,x,Subband,3*Subband+1 )
     ELSE IF ( A % Format == MATRIX_SBAND ) THEN
       CALL SolveSBandLapack( N,1,Values,x,Subband,Subband+1 )
     END IF

!------------------------------------------------------------------------------
  END SUBROUTINE BandSolver 
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Solves a linear system using Umfpack multifrontal direct solver courtesy
!> of University of Florida.
!------------------------------------------------------------------------------
  SUBROUTINE UMFPack_SolveSystem( Solver,A,x,b,Free_Fact )
!------------------------------------------------------------------------------
    LOGICAL, OPTIONAL :: Free_Fact
    TYPE(Matrix_t) :: A
    TYPE(Solver_t) :: Solver
    REAL(KIND=dp), TARGET :: x(*), b(*)

    REAL(KIND=dp), POINTER  :: Values(:)
    INTEGER, POINTER  :: Rows(:), Cols(:), Diag(:)









  ! Standard int version
  INTERFACE
    SUBROUTINE umf4def( control ) &
       BIND(C,name='umf4def')
       USE, INTRINSIC :: ISO_C_BINDING
       REAL(C_DOUBLE) :: control(*)
    END SUBROUTINE umf4def

    SUBROUTINE umf4sym( m,n,rows,cols,values,symbolic,control,iinfo ) &
       BIND(C,name='umf4sym')
       USE, INTRINSIC :: ISO_C_BINDING
       INTEGER(C_INT) :: m,n,rows(*),cols(*)
       INTEGER(c_int64_t) ::  symbolic
       REAL(C_DOUBLE) :: Values(*), control(*),iinfo(*)
    END SUBROUTINE umf4sym

    SUBROUTINE umf4num( rows,cols,values,symbolic,numeric, control,iinfo ) &
       BIND(C,name='umf4num')
       USE, INTRINSIC :: ISO_C_BINDING
       INTEGER(C_INT) :: rows(*),cols(*)
       INTEGER(c_int64_t) ::  numeric, symbolic
       REAL(C_DOUBLE) :: Values(*), control(*),iinfo(*)
    END SUBROUTINE umf4num

    SUBROUTINE umf4sol( sys, x, b, numeric, control, iinfo ) &
       BIND(C,name='umf4sol')
       USE, INTRINSIC :: ISO_C_BINDING
       INTEGER(C_INT) :: sys
       INTEGER(c_int64_t) :: numeric
       REAL(C_DOUBLE) :: x(*), b(*), control(*), iinfo(*)
    END SUBROUTINE umf4sol

    SUBROUTINE umf4fsym(symbolic) &
        BIND(C,name='umf4fsym')
        USE, INTRINSIC :: ISO_C_BINDING
        INTEGER(c_int64_t) :: symbolic
    END SUBROUTINE umf4fsym

    SUBROUTINE umf4fnum(numeric) &
        BIND(C,name='umf4fnum')
        USE, INTRINSIC :: ISO_C_BINDING
        INTEGER(c_int64_t) :: numeric
    END SUBROUTINE umf4fnum

  END INTERFACE

  ! Long int version
  INTERFACE
    SUBROUTINE umf4_l_def( control ) &
       BIND(C,name='umf4_l_def')
       USE, INTRINSIC :: ISO_C_BINDING
       REAL(C_DOUBLE) :: control(*)
    END SUBROUTINE umf4_l_def

    SUBROUTINE umf4_l_sym( m,n,rows,cols,values,symbolic,control,iinfo ) &
       BIND(C,name='umf4_l_sym')
       USE, INTRINSIC :: ISO_C_BINDING
       !INTEGER(c_int64_t) ::m,n,rows(*),cols(*) 
       INTEGER(C_LONG) :: m,n,rows(*),cols(*) !TODO: m,n of are called with AddrInt kind
       INTEGER(c_int64_t) ::  symbolic
       REAL(C_DOUBLE) :: Values(*), control(*),iinfo(*)
    END SUBROUTINE umf4_l_sym

    SUBROUTINE umf4_l_num( rows,cols,values,symbolic,numeric, control,iinfo ) &
       BIND(C,name='umf4_l_num')
       USE, INTRINSIC :: ISO_C_BINDING
       !INTEGER(c_int64_t) :: rows(*),cols(*)
       INTEGER(C_LONG) :: rows(*),cols(*)
       INTEGER(c_int64_t) ::  numeric, symbolic
       REAL(C_DOUBLE) :: Values(*), control(*),iinfo(*)
    END SUBROUTINE umf4_l_num

    SUBROUTINE umf4_l_sol( sys, x, b, numeric, control, iinfo ) &
       BIND(C,name='umf4_l_sol')
       USE, INTRINSIC :: ISO_C_BINDING
       !INTEGER(c_int64_t) :: sys
       INTEGER(C_LONG) :: sys
       INTEGER(c_int64_t) :: numeric
       REAL(C_DOUBLE) :: x(*), b(*), control(*), iinfo(*)
    END SUBROUTINE umf4_l_sol

    SUBROUTINE umf4_l_fnum(numeric) &
        BIND(C,name='umf4_l_fnum')
        USE, INTRINSIC :: ISO_C_BINDING
        INTEGER(c_int64_t) :: numeric
    END SUBROUTINE umf4_l_fnum

    SUBROUTINE umf4_l_fsym(symbolic) &
        BIND(C,name='umf4_l_fsym')
        USE, INTRINSIC :: ISO_C_BINDING
        INTEGER(c_int64_t) :: symbolic
    END SUBROUTINE umf4_l_fsym
  END INTERFACE

  INTEGER :: i, n, status, sys
  REAL(KIND=dp) :: iInfo(90), Control(20)
  INTEGER(KIND=AddrInt) :: symbolic, zero=0
  INTEGER(KIND=C_LONG) :: ln, lsys
  INTEGER(KIND=C_LONG), ALLOCATABLE :: LRows(:), LCols(:)

  SAVE iInfo, Control
 
  LOGICAL :: Factorize, FreeFactorize, stat, BigMode

  IF ( PRESENT(Free_Fact) ) THEN
    IF ( Free_Fact ) THEN
      IF ( A % UMFPack_Numeric/=0 ) THEN
        CALL umf4fnum(A % UMFPack_Numeric)
        A % UMFPack_Numeric = 0
      END IF
      RETURN
    END IF
  END IF

  BigMode = ListGetString( Solver % Values, &
      'Linear System Direct Method' ) == 'big umfpack'

  Factorize = ListGetLogical( Solver % Values, &
     'Linear System Refactorize', stat )
  IF ( .NOT. stat ) Factorize = .TRUE.

  n = A % NumberofRows
  Rows => A % Rows
  Cols => A % Cols
  Diag => A % Diag
  Values => A % Values

  IF ( Factorize .OR. A% UmfPack_Numeric==0 ) THEN
    IF ( A % UMFPack_Numeric /= 0 ) THEN
      IF( BigMode ) THEN
        CALL umf4_l_fnum( A % UMFPack_Numeric )
      ELSE
        CALL umf4fnum( A % UMFPack_Numeric )
      END IF
      A % UMFPack_Numeric = 0
    END IF

    IF ( BigMode ) THEN
      ALLOCATE( LRows(SIZE(Rows)), LCols(SIZE(Cols)) )

      DO i=1,n+1
        LRows(i) = Rows(i)-1
      END DO

      DO i=1,SIZE(Cols)
        LCols(i) = Cols(i)-1
      END DO

      ln = n ! TODO: Kludge: ln is AddrInt and n is regular INTEGER
      CALL umf4_l_def( Control )
      CALL umf4_l_sym( ln,ln, LRows, LCols, Values, Symbolic, Control, iInfo )
    ELSE
      Rows = Rows-1
      Cols = Cols-1
      CALL umf4def( Control )
      CALL umf4sym( n,n, Rows, Cols, Values, Symbolic, Control, iInfo )
    END IF

    IF (iInfo(1)<0) THEN
      PRINT *, 'Error occurred in umf4sym: ', iInfo(1)
      STOP EXIT_ERROR
    END IF

    IF ( BigMode ) THEN
      CALL umf4_l_num(LRows, LCols, Values, Symbolic, A % UMFPack_Numeric, Control, iInfo )
    ELSE
      CALL umf4num( Rows, Cols, Values, Symbolic, A % UMFPack_Numeric, Control, iInfo )
    END IF

    IF (iinfo(1)<0) THEN
      PRINT*, 'Error occurred in umf4num: ', iinfo(1)
      STOP EXIT_ERROR
    ENDIF

    IF ( BigMode ) THEN
      DEALLOCATE( LRows, LCols )
      CALL umf4_l_fsym( Symbolic )
    ELSE
      A % Rows = A % Rows+1
      A % Cols = A % Cols+1
      CALL umf4fsym( Symbolic )
    END IF
  END IF

  IF ( BigMode ) THEN
    lsys = 2
    CALL umf4_l_sol( lsys, x, b, A % UMFPack_Numeric, Control, iInfo )
  ELSE
    sys = 2
    CALL umf4sol( sys, x, b, A % UMFPack_Numeric, Control, iInfo )
  END IF

  IF (iinfo(1)<0) THEN
    PRINT*, 'Error occurred in umf4sol: ', iinfo(1)
    STOP EXIT_ERROR
  END IF
 
  FreeFactorize = ListGetLogical( Solver % Values, &
      'Linear System Free Factorization', stat )
  IF ( .NOT. stat ) FreeFactorize = .TRUE.

  IF ( Factorize .AND. FreeFactorize ) THEN
    IF ( BigMode ) THEN
      CALL umf4_l_fnum(A % UMFPack_Numeric)
    ELSE
      CALL umf4fnum(A % UMFPack_Numeric)
    END IF
    A % UMFPack_Numeric = 0
  END IF



!------------------------------------------------------------------------------
  END SUBROUTINE UMFPack_SolveSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Solves a linear system using Cholmod multifrontal direct solver courtesy
!> of University of Florida.
!------------------------------------------------------------------------------
  SUBROUTINE Cholmod_SolveSystem( Solver,A,x,b,Free_fact)
!------------------------------------------------------------------------------
  LOGICAL, OPTIONAL :: Free_Fact
  TYPE(Matrix_t) :: A
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp) :: x(*), b(*)

  INTERFACE
     SUBROUTINE cholmod_ffree(chol) BIND(c,NAME="cholmod_ffree")
       USE Types
       INTEGER(KIND=AddrInt) :: chol
     END SUBROUTINE cholmod_ffree

     FUNCTION cholmod_ffactorize(n,rows,cols,vals,cmplx) RESULT(chol) BIND(c,NAME="cholmod_ffactorize")
        USE Types
        INTEGER :: n, cmplx, Rows(*), Cols(*)
        REAL(KIND=dp) :: Vals(*)
        INTEGER(KIND=dp) :: chol
     END FUNCTION cholmod_ffactorize

     SUBROUTINE cholmod_fsolve(chol, n, x,b) BIND(c,NAME="cholmod_fsolve")
        USE Types
        REAL(KIND=dp) :: x(*), b(*)
        INTEGER :: n
        INTEGER(KIND=dp) :: chol
     END SUBROUTINE cholmod_fsolve
  END INTERFACE

  LOGICAL :: Factorize, FreeFactorize, Found
  INTEGER :: i
  REAL(KIND=dp), POINTER  :: Vals(:)
  INTEGER, POINTER  :: Rows(:), Cols(:), Diag(:)

# 617 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'Cholmod_SolveSystem', 'Cholmod Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE Cholmod_SolveSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Solves a linear system using SuiteSparseQR multifrontal direct solver courtesy
!> of University of Florida.
!------------------------------------------------------------------------------
  SUBROUTINE SPQR_SolveSystem( Solver,A,x,b,Free_fact)
!------------------------------------------------------------------------------
  LOGICAL, OPTIONAL :: Free_Fact
  TYPE(Matrix_t) :: A
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp) :: x(*), b(*)

  INTEGER :: i
  LOGICAL :: Factorize, FreeFactorize, Found

  REAL(KIND=dp), POINTER  :: Vals(:)
  INTEGER, POINTER  :: Rows(:), Cols(:), Diag(:)

  INTERFACE
     FUNCTION spqr_ffree(chol) RESULT(stat) BIND(c,NAME="spqr_ffree")
       USE Types
       INTEGER :: stat
       INTEGER(KIND=AddrInt) :: chol
     END FUNCTION spqr_ffree

     FUNCTION spqr_ffactorize(n,rows,cols,vals) RESULT(chol) BIND(c,NAME="spqr_ffactorize")
       USE Types
       INTEGER :: n, rows(*), cols(*)
       REAL(KIND=dp) :: vals(*)
       INTEGER(KIND=AddrInt) :: chol
     END FUNCTION spqr_ffactorize

     SUBROUTINE spqr_fsolve(chol, n, x,b) BIND(c,NAME="spqr_fsolve")
       USE Types
       REAL(KIND=dp) :: x(*), b(*)
       INTEGER :: n
       INTEGER(KIND=AddrInt) :: chol
     END SUBROUTINE spqr_fsolve
  END INTERFACE

# 703 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'SPQR_SolveSystem', 'SPQR Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE SPQR_SolveSystem
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
 SUBROUTINE FreeMumpsFactorizations(A)
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A

!------------------------------------------------------------------------------
# 777 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
!------------------------------------------------------------------------------
 END SUBROUTINE FreeMumpsFactorizations
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Solves a linear system using MUMPS direct solver. This is a legacy solver
!> with complicated dependencies. Single precision version.
!------------------------------------------------------------------------------
  SUBROUTINE SMumps_SolveSystem( Solver,A,x,b )
!------------------------------------------------------------------------------






  TYPE(Matrix_t) :: A
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp), TARGET :: x(*), b(*)

# 986 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'Mumps_SolveSystem', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE SMumps_SolveSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Solves a linear system using MUMPS direct solver. This is a legacy solver
!> with complicated dependencies. Single precision complex version.
!------------------------------------------------------------------------------
  SUBROUTINE CMumps_SolveSystem( Solver,A,x,b )
!------------------------------------------------------------------------------






  TYPE(Matrix_t) :: A
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp), TARGET :: x(*), b(*)

# 1201 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'Mumps_SolveSystem', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE CMumps_SolveSystem
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Solves a linear system using MUMPS direct solver. This is a legacy solver
!> with complicated dependencies. This is only available in parallel. 
!------------------------------------------------------------------------------
  SUBROUTINE Mumps_SolveSystem( Solver,A,x,b )
!------------------------------------------------------------------------------






  TYPE(Matrix_t) :: A
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp), TARGET :: x(*), b(*)

# 1410 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'Mumps_SolveSystem', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE Mumps_SolveSystem
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Solves a complex linear system using MUMPS direct solver. This is a legacy solver
!> with complicated dependencies. This is only available in parallel. 
!------------------------------------------------------------------------------
  SUBROUTINE ZMumps_SolveSystem( Solver,A,x,b )
!------------------------------------------------------------------------------






  TYPE(Matrix_t) :: A
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp), TARGET :: x(*), b(*)

# 1618 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'ZMumps_SolveSystem', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE ZMumps_SolveSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Solves local linear system using MUMPS direct solver. If the solved system
!> is singular, optionally one possible solution is returned.
!------------------------------------------------------------------------------
  SUBROUTINE MumpsLocal_SolveSystem( Solver, A, x, b, Free_Fact )
!------------------------------------------------------------------------------
     IMPLICIT NONE

     TYPE(Matrix_t) :: A
     TYPE(Solver_t) :: Solver
     REAL(KIND=dp), TARGET :: x(*), b(*)
     LOGICAL, OPTIONAL :: Free_Fact

     INTEGER :: i
     LOGICAL :: Factorize, FreeFactorize, stat

# 1687 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
     CALL Fatal( 'MumpsLocal_SolveSystem', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE MumpsLocal_SolveSystem
!------------------------------------------------------------------------------

  !------------------------------------------------------------------------------
!> Solves local linear system using MUMPS direct solver. If the solved system
!> is singular, optionally one possible solution is returned.
!------------------------------------------------------------------------------
  SUBROUTINE ZMumpsLocal_SolveSystem( Solver, A, x, b, Free_Fact )
!------------------------------------------------------------------------------
     IMPLICIT NONE

     TYPE(Matrix_t) :: A
     TYPE(Solver_t) :: Solver
     REAL(KIND=dp), TARGET :: x(*), b(*)
     LOGICAL, OPTIONAL :: Free_Fact

     INTEGER :: i,j
     LOGICAL :: Factorize, FreeFactorize, stat

# 1758 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
     CALL Fatal( 'ZMumpsLocal_SolveSystem', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
   END SUBROUTINE ZMumpsLocal_SolveSystem
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Factorize local matrix with Mumps
!------------------------------------------------------------------------------
  SUBROUTINE MumpsLocal_Factorize(Solver, A)
!------------------------------------------------------------------------------





    IMPLICIT NONE

    TYPE(Solver_t) :: Solver
    TYPE(Matrix_t) :: A

# 1938 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'MumpsLocal_Factorize', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE MumpsLocal_Factorize
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Factorize local matrix with Mumps
!------------------------------------------------------------------------------
  SUBROUTINE ZMumpsLocal_Factorize(Solver, A)
!------------------------------------------------------------------------------





    IMPLICIT NONE

    TYPE(Solver_t) :: Solver
    TYPE(Matrix_t) :: A

# 2117 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'ZMumpsLocal_Factorize', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
 END SUBROUTINE ZMumpsLocal_Factorize
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Solve local nullspace using MUMPS direct solver. On exit, z will be
!> allocated and will hold the jth local nullspace vectors as z(j,:).
!------------------------------------------------------------------------------
  SUBROUTINE MumpsLocal_SolveNullSpace(Solver, A, z, nz)
!------------------------------------------------------------------------------





      IMPLICIT NONE

      TYPE(Solver_t) :: Solver
      TYPE(Matrix_t) :: A
      REAL(KIND=dp), ALLOCATABLE, DIMENSION(:,:), TARGET :: z
      INTEGER :: nz, nrhs

# 2224 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'MumpsLocal_SolveNullSpace', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE MumpsLocal_SolveNullSpace
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Free local Mumps variables and solver internal allocations
!------------------------------------------------------------------------------
  SUBROUTINE MumpsLocal_Free(A)
!------------------------------------------------------------------------------
        IMPLICIT NONE

        TYPE(Matrix_t) :: A

# 2265 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
     CALL Fatal( 'MumpsLocal_Free', 'MUMPS Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE MumpsLocal_Free
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
!> Solves a linear system using SuperLU direct solver.
!------------------------------------------------------------------------------
  SUBROUTINE SuperLU_SolveSystem( Solver,A,x,b,Free_Fact )
!------------------------------------------------------------------------------
  LOGICAL, OPTIONAL :: Free_fact
  TYPE(Matrix_t) :: A
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp), TARGET :: x(*), b(*)

# 2367 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
!------------------------------------------------------------------------------
  END SUBROUTINE SuperLU_SolveSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Permon solver
!------------------------------------------------------------------------------
  SUBROUTINE Permon_SolveSystem( Solver,A,x,b,Free_Fact )
!------------------------------------------------------------------------------







  LOGICAL, OPTIONAL :: Free_Fact
  TYPE(Matrix_t) :: A
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp), TARGET :: x(*), b(*)

# 2483 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
   CALL Fatal( 'Permon_SolveSystem', 'Permon Solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE Permon_SolveSystem
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
!> Solves a linear system using Pardiso direct solver (from either MKL or
!> official Pardiso distribution. If possible, MKL-version is used).
!------------------------------------------------------------------------------
  SUBROUTINE Pardiso_SolveSystem( Solver,A,x,b,Free_fact )
!------------------------------------------------------------------------------
    IMPLICIT NONE

    TYPE(Solver_t) :: Solver
    TYPE(Matrix_t) :: A
    REAL(KIND=dp), TARGET :: x(*), b(*)
    LOGICAL, OPTIONAL :: Free_fact

! MKL version of Pardiso (interface is different)
# 2909 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
      CALL Fatal( 'Parsido_SolveSystem', 'Pardiso solver has not been installed.' )


!------------------------------------------------------------------------------
  END SUBROUTINE Pardiso_SolveSystem
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Solves a linear system using Cluster Pardiso direct solver from MKL
!------------------------------------------------------------------------------
  SUBROUTINE CPardiso_SolveSystem( Solver,A,x,b,Free_fact )
!------------------------------------------------------------------------------
    IMPLICIT NONE

    TYPE(Solver_t) :: Solver
    TYPE(Matrix_t) :: A
    REAL(KIND=dp), TARGET :: x(*), b(*)
    LOGICAL, OPTIONAL :: Free_fact

! Cluster Pardiso
# 3013 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
    CALL Fatal( 'CParsido_SolveSystem', 'Cluster Pardiso solver has not been installed.' )

!------------------------------------------------------------------------------
  END SUBROUTINE CPardiso_SolveSystem
!------------------------------------------------------------------------------

# 3342 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"


!------------------------------------------------------------------------------
  SUBROUTINE DirectSolver( A,x,b,Solver,Free_Fact )
!------------------------------------------------------------------------------

    TYPE(Solver_t) :: Solver
    REAL(KIND=dp) :: x(*),b(*)
    TYPE(Matrix_t) :: A
    LOGICAL, OPTIONAL :: Free_Fact
!------------------------------------------------------------------------------

    LOGICAL :: GotIt
    CHARACTER(:), ALLOCATABLE :: Method
!------------------------------------------------------------------------------

    IF ( PRESENT(Free_Fact) ) THEN
      IF ( Free_Fact ) THEN
        CALL BandSolver( A, x, b, Free_Fact )
        CALL ComplexBandSolver( A, x, b, Free_Fact )
# 3376 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
        CALL Umfpack_SolveSystem( Solver, A, x, b, Free_Fact )
# 3385 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/DirectSolve.F90"
        RETURN
      END IF
    END IF

    Method=ListGetString(Solver % Values,'Linear System Direct Method',GotIt)
    IF ( .NOT. GotIt ) Method = 'banded'
    
    
    CALL Info('DirectSolver','Using direct method: '//Method,Level=9)








    SELECT CASE(Method)
      CASE( 'banded', 'symmetric banded' )
        IF ( .NOT. A % Complex ) THEN
           CALL BandSolver( A, x, b )
        ELSE
           CALL ComplexBandSolver( A, x, b )
        END IF

      CASE( 'umfpack', 'big umfpack' )
        CALL Umfpack_SolveSystem( Solver, A, x, b )

      CASE( 'cholmod' )
        CALL Cholmod_SolveSystem( Solver, A, x, b )

      CASE( 'spqr' )
        CALL SPQR_SolveSystem( Solver, A, x, b )

      CASE( 'smumps', 'cmumps' )
        IF( A % Complex ) THEN
          CALL CMumps_SolveSystem( Solver, A, x, b )
        ELSE
          CALL SMumps_SolveSystem( Solver, A, x, b )
        END IF

      CASE( 'mumps', 'dmumps', 'zmumps' )
        IF( A % Complex ) THEN
          CALL ZMumps_SolveSystem( Solver, A, x, b )
        ELSE
          CALL Mumps_SolveSystem( Solver, A, x, b )
        END IF

      CASE( 'mumpslocal' )
        IF( A % Complex ) THEN
          CALL ZMumpsLocal_SolveSystem( Solver, A, x, b )
        ELSE
          CALL MumpsLocal_SolveSystem( Solver, A, x, b )
        END IF
          
      CASE( 'superlu' )
        CALL SuperLU_SolveSystem( Solver, A, x, b )

      CASE( 'permon' )
        CALL Permon_SolveSystem( Solver, A, x, b )

      CASE( 'pardiso' )
        CALL Pardiso_SolveSystem( Solver, A, x, b )

      CASE( 'cpardiso' )
        CALL CPardiso_SolveSystem( Solver, A, x, b )

      CASE DEFAULT
        CALL Fatal( 'DirectSolver', 'Unknown direct solver method.' )
    END SELECT

    ! We should be able to trust that a direct strategy will return a converged
    ! linear system.
    IF( ASSOCIATED( Solver % Variable ) ) THEN
      Solver % Variable % LinConverged = 1
    END IF
    
!------------------------------------------------------------------------------
  END SUBROUTINE DirectSolver
!------------------------------------------------------------------------------

END MODULE DirectSolve

!> \} ElmerLib
