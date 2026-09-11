# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/BandMatrix.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/BandMatrix.F90"
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
# 36 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/BandMatrix.F90"


# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_fdefs.h" 1

! Fortran preprocessor definitions for HUTIter library
!
! $Id: huti_fdefs.h,v 1.1.1.1 2005/04/15 10:31:18 vierinen Exp $




! HUTI defaults








! HUTI status flags






						
! QMR method







! CG method



! CGS method



! TFQMR method



! BiCGSTAB method





! GMRES method




! BiCGSTAB(2) method



! HUTI debug levels




! Initial X for solvers




! Matrix type in external operations




! Storage allocation for various methods









! Different stopping criteria

# 96 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_fdefs.h"

!
! HUTI ipar structure (used for various parameters)
!



! Input parameters supplied by user or by initialization
!
! General parameters (1-9)








						
! Iteration parameters (10-19)

# 127 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_fdefs.h"
						
! Parallel environment parameters (20-29)



! Robust methods




  
! Output parameters (30-39)
!




!
! HUTI dpar structure (used for various parameters)
!



! Input parameters supplied by user









						 !  
! End of definitions
!

# 38 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/BandMatrix.F90" 2

!> \ingroup ElmerLib 
!> \{

!-------------------------------------------------------------------------------
!>  Module defining utility routines & matrix storage for band matrix format.
!>  This module is currently of no or, only little use as the default 
!> matrix storage format is CRS. 
!-------------------------------------------------------------------------------

MODULE BandMatrix

  USE GeneralUtils

  IMPLICIT NONE

CONTAINS




!------------------------------------------------------------------------------
!> Zero a Band format matrix
!------------------------------------------------------------------------------
  SUBROUTINE Band_ZeroMatrix(A)
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A   !< Structure holding matrix

    A % Values = 0.0D0
    IF ( ASSOCIATED( A % MassValues ) ) A % MassValues = 0.0d0
    IF ( ASSOCIATED( A % DampValues ) ) A % DampValues = 0.0d0
  END SUBROUTINE Band_ZeroMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Zero given row from a Band format matrix
!------------------------------------------------------------------------------
  SUBROUTINE Band_ZeroRow( A,n )
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A  !< Structure holding matrix
    INTEGER :: n                  !< Row number to be zerod
!------------------------------------------------------------------------------
 
    INTEGER :: j,k

    IF ( A % Format == MATRIX_BAND ) THEN
      DO j=MAX(1,n-A % Subband), MIN(A % NumberOfRows, n+A % Subband)
        A % Values((((j)-1)*(3*A % Subband+1) + (n)-(j)+2*A % Subband+1)) = 0.0d0
      END DO
    ELSE
      DO j=MAX(1,n-A % Subband),n
        A % Values((((j)-1)*(A % Subband+1) + (n)-(j)+1)) = 0.0d0
      END DO
    END IF
  END SUBROUTINE Band_ZeroRow
!------------------------------------------------------------------------------
  
!------------------------------------------------------------------------------
!> Add a given element to the band matrix.
!------------------------------------------------------------------------------
  SUBROUTINE Band_AddToMatrixElement( A,i,j,value )
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A  !< Structure holding matrix
    INTEGER :: i  !< row number of the matrix element
    INTEGER :: j  !< column number of the matrix element
    REAL(KIND=dp) :: value  !< Value to be added
!------------------------------------------------------------------------------
    INTEGER :: k
!------------------------------------------------------------------------------
    IF ( A % Format == MATRIX_BAND ) THEN
      k = (((j)-1)*(3*A % Subband+1) + (i)-(j)+2*A % Subband+1)
      A % Values(k) = A % Values(k) + Value
    ELSE
      IF ( j <= i ) THEN
        k = (((j)-1)*(A % Subband+1) + (i)-(j)+1)
        A % Values(k) = A % Values(k) + Value
       END IF
    END IF
  END SUBROUTINE Band_AddToMatrixElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Set a given element in the band matrix.
!------------------------------------------------------------------------------
  SUBROUTINE Band_SetMatrixElement( A,i,j,value )
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A  !< Structure holding matrix
    INTEGER :: i  !< row number of the matrix element
    INTEGER :: j  !< column number of the matrix element
    REAL(KIND=dp) :: value  !< Value to be set
!------------------------------------------------------------------------------

    IF ( A % Format == MATRIX_BAND ) THEN
      A % Values((((j)-1)*(3*A % Subband+1) + (i)-(j)+2*A % Subband+1))  = Value
    ELSE
      IF ( j <= i ) A % Values((((j)-1)*(A % Subband+1) + (i)-(j)+1)) = Value
    END IF
  END SUBROUTINE Band_SetMatrixElement
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Get a given matrix element of a band matrix format.
!------------------------------------------------------------------------------
  FUNCTION Band_GetMatrixElement( A,i,j ) RESULT ( value )
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A  !< Structure holding matrix
    INTEGER :: i  !< row number of the matrix element
    INTEGER :: j  !< column number of the matrix element
    REAL(KIND=dp) :: value  !< Value to be obtained
!------------------------------------------------------------------------------
    IF ( A % Format == MATRIX_BAND ) THEN
      Value = A % Values((((j)-1)*(3*A % Subband+1) + (i)-(j)+2*A % Subband+1))  
    ELSE
      IF ( j <= i ) Value = A % Values((((j)-1)*(A % Subband+1) + (i)-(j)+1)) 
    END IF
  END FUNCTION Band_GetMatrixElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Add a set of values (.i.e. element stiffness matrix) to a Band format matrix. 
!------------------------------------------------------------------------------
  SUBROUTINE Band_GlueLocalMatrix( A,N,Dofs,Indeces,LocalMatrix )
!------------------------------------------------------------------------------ 
     REAL(KIND=dp) :: LocalMatrix(:,:)  !< A (N x Dofs) x ( N x Dofs) matrix holding the values to be
                                        !! added to the Band format matrix
     TYPE(Matrix_t) :: A   !< Structure holding matrix, values are affected in the process
     INTEGER :: N                   !< Number of nodes in element
     INTEGER :: Dofs                !< Number of degrees of freedom for one node
     INTEGER :: Indeces(:)          !< Maps element node numbers to global (or partition) node numbers
                                    !! (to matrix rows and columns, if Dofs = 1)
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     INTEGER :: i,j,k,l,c,ind,Row,Col
     REAL(KIND=dp), POINTER :: Values(:)
!------------------------------------------------------------------------------

      Values => A % Values

     IF ( A % Format == MATRIX_BAND ) THEN
       DO i=1,N
         DO k=0,Dofs-1
           Row = Dofs * Indeces(i) - k
           DO j=1,N
             DO l=0,Dofs-1
               Col = Dofs * Indeces(j) - l
               ind = (((Col)-1)*(3*A % Subband+1) + (Row)-(Col)+2*A % Subband+1)
               Values(ind) = &
                  Values(ind) + LocalMatrix(Dofs*i-k,Dofs*j-l)
             END DO
           END DO
         END DO
       END DO
     ELSE
       DO i=1,N
         DO k=0,Dofs-1
           Row = Dofs * Indeces(i) - k
           DO j=1,N
             DO l=0,Dofs-1
               Col = Dofs * Indeces(j) - l
               IF ( Col <= Row ) THEN
                 ind = (((Col)-1)*(A % Subband+1) + (Row)-(Col)+1)
                 Values(ind) = &
                    Values(ind) + LocalMatrix(Dofs*i-k,Dofs*j-l)
               END IF
             END DO
           END DO
         END DO
       END DO
     END IF

  END SUBROUTINE Band_GlueLocalMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!>    Set value of unknown x_n to given value for symmetric band matrix. This is
!>    done by replacing the equation of the unknown by  x_n = Value (i.e.
!>    zeroing the row of the unknown in the matrix, and setting diagonal to
!>    identity). Also the respective column is set to zero (except for the
!>    diagonal) to preserve symmetry, while also substituting the rhs by
!>    by rhs(i) = rhs(i) - A(i,n) * Value.
!------------------------------------------------------------------------------
  SUBROUTINE SBand_SetDirichlet( A, b, n, Value )
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A  !< Structure holding matrix, values are affected in the process
    REAL(KIND=dp) :: b(:)         !< RHS vector
    REAL(KIND=dp), INTENT(IN) :: Value        !< Value for the unknown
    INTEGER, INTENT(IN) :: n                  !< Ordered number of the unknown (i.e. matrix row and column number)
!------------------------------------------------------------------------------

    INTEGER :: j
!------------------------------------------------------------------------------

    DO j=MAX(1,n-A % Subband),n-1
      b(j) = b(j) - Value * A % Values((((j)-1)*(A % Subband+1) + (n)-(j)+1))
      A % Values((((j)-1)*(A % Subband+1) + (n)-(j)+1)) = 0.0d0
    END DO

    DO j=n+1,MIN(n+A % Subband, A % NumberOfRows)
      b(j) = b(j) - Value * A % Values((((n)-1)*(A % Subband+1) + (j)-(n)+1))
      A % Values((((n)-1)*(A % Subband+1) + (j)-(n)+1)) = 0.0d0
    END DO

    b(n) = Value
    A % Values((((n)-1)*(A % Subband+1) + (n)-(n)+1)) = 1.0d0
!------------------------------------------------------------------------------
  END SUBROUTINE SBand_SetDirichlet
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
!> Create the structures required for a Band format matrix.
!------------------------------------------------------------------------------
  FUNCTION Band_CreateMatrix( N,Subband,Symmetric,AllocValues ) RESULT(A)
!------------------------------------------------------------------------------
    INTEGER :: N        !< Number of rows for the matrix
    INTEGER :: Subband  !< Max(ABS(Col-Diag(Row))) of the matrix
    LOGICAL :: Symmetric !< Symmetric or not
    LOGICAL :: AllocValues  !< Should the values arrays be allocated ?
    TYPE(Matrix_t), POINTER :: A  !< Pointer to the created Matrix_t structure.
!------------------------------------------------------------------------------
    INTEGER :: i,j,k,istat
!------------------------------------------------------------------------------

    A => AllocateMatrix()

    A % Subband = Subband
    A % NumberOfRows = N

    IF ( AllocValues ) THEN
      IF ( Symmetric ) THEN
        ALLOCATE( A % Values((A % Subband+1)*N), STAT=istat )
      ELSE
        ALLOCATE( A % Values((3*A % Subband+1)*N), STAT=istat )
      END IF
    END IF

    IF ( istat /= 0 ) THEN
      CALL Fatal( 'Band_CreateMatrix', 'Memory allocation error.' )
    END IF

    NULLIFY( A % ILUValues )
  END FUNCTION Band_CreateMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Matrix vector product (v = Au) for a matrix given in Band format.
!------------------------------------------------------------------------------
  SUBROUTINE Band_MatrixVectorMultiply( A,u,v )
!------------------------------------------------------------------------------
    REAL(KIND=dp), DIMENSION(*) :: u  !< vector to be multiplied
    REAL(KIND=dp), DIMENSION(*) :: v  !< result vector
    TYPE(Matrix_t) :: A      !< Structure holding the matrix
!------------------------------------------------------------------------------
    REAL(KIND=dp), POINTER :: Values(:)

    INTEGER :: i,j,k,n
    REAL(KIND=dp) :: s
!------------------------------------------------------------------------------

    Values => A % Values
    n = A % NumberOfRows

    IF ( A % Format == MATRIX_BAND ) THEN
      DO i=1,n
        s = 0.0d0
        DO j=MAX(1,i-A % Subband), MIN(n,i+A % Subband)
          s = s + u(j) * Values((((j)-1)*(3*A % Subband+1) + (i)-(j)+2*A % Subband+1))
        END DO
        v(i) = s
      END DO
    ELSE
      DO i=1,n
        s = 0.0d0
        DO j=MAX(1,i-A % Subband),i
          s = s + u(j) * Values((((j)-1)*(A % Subband+1) + (i)-(j)+1))
        END DO

        DO j=i+1,MIN(i+A % Subband, A % NumberOfRows)
          s = s + u(j) * Values((((i)-1)*(A % Subband+1) + (j)-(i)+1))
        END DO
        v(i) = s
      END DO
    END IF

  END SUBROUTINE Band_MatrixVectorMultiply
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Matrix vector product (v = Au) for a matrix given in Band format. The
!> matrix is accessed from a global variable GlobalMatrix.
!------------------------------------------------------------------------------
  SUBROUTINE Band_MatrixVectorProd( u,v,ipar )
!------------------------------------------------------------------------------
    REAL(KIND=dp), DIMENSION(*) :: u !< Vector to be multiplied
    REAL(KIND=dp), DIMENSION(*) :: v !< Result vector of the multiplication
    INTEGER, DIMENSION(*) :: ipar  !< structure holding info from (HUTIter-iterative solver package)
!------------------------------------------------------------------------------
    REAL(KIND=dp), POINTER :: Values(:)

    TYPE(Matrix_t), POINTER :: A
    INTEGER :: i,j,k,n
    REAL(KIND=dp) :: s
!------------------------------------------------------------------------------
    A => GlobalMatrix

    Values => A % Values
    n = A % NumberOfRows

    IF ( A % Format == MATRIX_BAND ) THEN
      IF ( ipar(6) == 0 ) THEN
        DO i=1,n
          s = 0.0d0
          DO j=MAX(1,i-A % Subband), MIN(n,i+A % Subband)
            s = s + u(j) * Values((((j)-1)*(3*A % Subband+1) + (i)-(j)+2*A % Subband+1))
          END DO
          v(i) = s
        END DO
      ELSE
        v(1:n) = 0.0d0
        DO i=1,n
          s = u(i)
          DO j=MAX(1,i-A % Subband), MIN(n,i+A % Subband)
            v(j) = v(j) + s * Values((((j)-1)*(3*A % Subband+1) + (i)-(j)+2*A % Subband+1))
          END DO
        END DO
      END IF
    ELSE
      DO i=1,n
        s = 0.0d0
        DO j=MAX(1,i-A % Subband),i
          s = s + u(j) * Values((((j)-1)*(A % Subband+1) + (i)-(j)+1))
        END DO

        DO j=i+1,MIN(i+A % Subband, A % NumberOfRows)
          s = s + u(j) * Values((((i)-1)*(A % Subband+1) + (j)-(i)+1))
        END DO
        v(i) = s
      END DO
    END IF

  END SUBROUTINE Band_MatrixVectorProd
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
!> Diagonal preconditioning of a Band format matrix.
!------------------------------------------------------------------------------
  SUBROUTINE Band_DiagPrecondition( u,v,ipar )
!------------------------------------------------------------------------------
    REAL(KIND=dp), DIMENSION(*) :: u !< Vector to be multiplied
    REAL(KIND=dp), DIMENSION(*) :: v !< Result vector of the multiplication
    INTEGER, DIMENSION(*) :: ipar  !< structure holding info from (HUTIter-iterative solver package)
!------------------------------------------------------------------------------
    INTEGER :: i,j,k,n
    TYPE(Matrix_t), POINTER :: A

    REAL(KIND=dp), POINTER :: Values(:)

    A => GlobalMatrix
    Values => GlobalMatrix % Values

    n = A % NumberOfRows

    IF ( A % Format == MATRIX_BAND ) THEN
      DO i=1,n
        k = (((i)-1)*(3*A % Subband+1) + (i)-(i)+2*A % Subband+1)
        IF  ( ABS(Values(k)) > AEPS ) THEN
           u(i) = v(i) / Values(k)
        ELSE
           u(i) = v(i)
        END IF
      END DO
    ELSE 
      DO i=1,n
        k = (((i)-1)*(A % Subband+1) + (i)-(i)+1)
        IF  ( ABS(Values(k)) > AEPS ) THEN
          u(i) = v(i) / Values(k)
        ELSE
          u(i) = v(i)
        END IF
      END DO
    END IF
  END SUBROUTINE Band_DiagPrecondition
!------------------------------------------------------------------------------

END MODULE BandMatrix

!> \} ElmerLib

