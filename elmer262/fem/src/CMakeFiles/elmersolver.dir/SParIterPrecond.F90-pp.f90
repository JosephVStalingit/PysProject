# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/SParIterPrecond.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/SParIterPrecond.F90"
!
! *
! *  Elmer, A Finite Element Software for Multiphysical Problems
! *
! *  Copyright 1st April 1995 - , CSC - IT Center for Science Ltd., Finland
! * 
! * This library is free software; you can redistribute it and/or
! * modify it under the terms of the GNU Lesser General Public
! * License as published by the Free Software Foundation; either
! * version 2.1 of the License, or (at your option) any later version.
! *
! * This library is distributed in the hope that it will be useful,
! * but WITHOUT ANY WARRANTY; without even the implied warranty of
! * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
! * Lesser General Public License for more details.
! * 
! * You should have received a copy of the GNU Lesser General Public
! * License along with this library (in file ../LGPL-2.1); if not, write 
! * to the Free Software Foundation, Inc., 51 Franklin Street, 
! * Fifth Floor, Boston, MA  02110-1301  USA
! *
! *****************************************************************************/
!
! ******************************************************************************
! *
! *  Authors: Jouni Malinen, Juha Ruokolainen
! *  Email:   Juha.Ruokolainen@csc.fi
! *  Web:     http://www.csc.fi/elmer
! *  Address: CSC - IT Center for Science Ltd.
! *           Keilaranta 14
! *           02101 Espoo, Finland 
! *
! *  Original Date: 2000
! *
! *****************************************************************************/


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

# 38 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/SParIterPrecond.F90" 2

!------------------------------------------------------------------------------
!> External Preconditioning operations needed by parallel iterative solvers.
!> This is the place to do preconditioning steps if needed
!> Called from HUTIter library
!------------------------------------------------------------------------------
!> \ingroup ElmerLib
!> \{


MODULE SParIterPrecond

  USE SParIterComm

  IMPLICIT NONE
  
CONTAINS

  !----------------------------------------------------------------------
  !> Parallel diagonal preconditioning 
  !----------------------------------------------------------------------
  SUBROUTINE ParDiagPrec ( u, v, ipar )

    ! Input parameters

    DOUBLE PRECISION, DIMENSION(*) :: u, v
    INTEGER, DIMENSION(*) :: ipar

    ! Local parameters
    
    INTEGER :: i

    !*********************************************************************

    DO i = 1,ipar(3)
       u(i) = v(i) * PIGpntr % SplittedMatrix % InsideMatrix % ILUValues(i)
    END DO

  END SUBROUTINE ParDiagPrec


  !------------------------------------------------------------------------
  !> This routines performs a forward and backward solve for ILU
  !> factorization, i.e. solves (LU)u = v.
  !> Diagonal values of U must be already inverted
  !------------------------------------------------------------------------  
  SUBROUTINE ParLUPrec ( u, v, ipar )

    ! Input parameters

    DOUBLE PRECISION, DIMENSION(*) :: u, v
    INTEGER, DIMENSION(*) :: ipar

    ! Local parameters

    INTEGER :: i, k

    DOUBLE PRECISION, POINTER  :: Vals(:)
    INTEGER, POINTER  :: Rows(:),Cols(:),Diag(:)

    !*********************************************************************

    ! Forward solve, Lu = v

    Rows => PIGpntr % SplittedMatrix % InsideMatrix % Rows
    Cols => PIGpntr % SplittedMatrix % InsideMatrix % Cols
    Diag => PIGpntr % SplittedMatrix % InsideMatrix % Diag
    Vals => PIGpntr % SplittedMatrix % InsideMatrix % ILUValues

    CALL LUPrec( ipar(3), SIZE(Cols), Rows,Cols,Diag,Vals,u,v )

CONTAINS
    
    SUBROUTINE LUPrec( n,m,Rows,Cols,Diag,Vals,u,v )
    INTEGER :: n,m,Rows(n+1),Cols(m),Diag(n)
    DOUBLE PRECISION :: Vals(m),u(n),v(n)

    DO i = 1, n

       ! Compute u(i) = v(i) - sum L(i,j) u(j)

       u(i) = v(i)

       DO k = Rows(i), Diag(i) - 1
          u(i) = u(i) - Vals(k) * u(Cols(k))
       END DO

    END DO

    ! Backward solve, u = inv(U) u
    
    DO i = n, 1, -1

       ! Compute u(i) = u(i) - sum U(i,j) u(j)

       DO k = Diag(i)+1,Rows(i+1)-1
          u(i) = u(i) - Vals(k) * u(Cols(k))
       END DO

       ! Compute u(i) = u(i) / U(i,i)

       u(i) = Vals(Diag(i)) * u(i)

    END DO
    END SUBROUTINE LUPrec

  END SUBROUTINE ParLUPrec


  !------------------------------------------------------------------------
  !> This routines performs a forward solve for ILU
  !> factorization, i.e. solves Lu = v.
  !> Diagonal values of U must be already inverted
  !------------------------------------------------------------------------
  SUBROUTINE ParLPrec ( u, v, ipar )
    
    ! Input parameters

    DOUBLE PRECISION, DIMENSION(*) :: u, v
    INTEGER, DIMENSION(*) :: ipar

    ! Local parameters
    
    INTEGER :: i, k

    !*********************************************************************

    ! Forward solve, Lu = v

    DO i = 1, ipar(3)

       ! Compute u(i) = v(i) - sum L(i,j) u(j)
       
       u(i) = v(i)
       DO k = PIGpntr % SplittedMatrix % InsideMatrix % Rows(i), &
                 PIGpntr % SplittedMatrix % InsideMatrix % Diag(i) - 1
          u(i) = u(i) - PIGpntr % SplittedMatrix % InsideMatrix % ILUValues(k) &
               * u(PIGpntr % SplittedMatrix % InsideMatrix % Cols(k))
       END DO
    END DO

!    CALL UpdateOwnedVectorEl( PIGpntr, u, ipar(3) )

  END SUBROUTINE ParLPrec


  !-----------------------------------------------------------------------
  !> This routines performs backward solve for ILU
  !> factorization, i.e. solves Uu = v.
  !> Diagonal values of U must be already inverted.
  !-----------------------------------------------------------------------
  SUBROUTINE ParUPrec ( u, v, ipar )

    ! Input parameters

    DOUBLE PRECISION, DIMENSION(*) :: u, v
    INTEGER, DIMENSION(*) :: ipar

    ! Local parameters
    
    INTEGER :: i, k

    !*********************************************************************

    ! Backward solve, u = inv(U) u

    DO i = ipar(3), 1, -1

       ! Compute u(i) = u(i) - sum U(i,j) u(j)

       u(i) = v(i)
       DO k = PIGpntr % SplittedMatrix % InsideMatrix % Diag(i) + 1, &
             PIGpntr % SplittedMatrix % InsideMatrix % Rows(i+1) - 1
          u(i) = u(i) - PIGpntr % SplittedMatrix % InsideMatrix % ILUValues(k) &
               * u(PIGpntr % SplittedMatrix % InsideMatrix % Cols(k))
       END DO
       
       ! Compute u(i) = u(i) / U(i,i)

       u(i) = PIGpntr % SplittedMatrix % InsideMatrix % ILUValues( &
              PIGpntr % SplittedMatrix % InsideMatrix % Diag(i)) * u(i)
    END DO

!    CALL UpdateOwnedVectorEl( PIGpntr, u, ipar(3) )

  END SUBROUTINE ParUPrec


  !-----------------------------------------------------------------------
  !> This routine is used to perform ILU(0) preconditioning setup
  !> Incomplete LU factorization is saved to Matrix % ILUValues.
  !> Diagonal entries are inverted.
  !-----------------------------------------------------------------------
  
  SUBROUTINE ParILU0 ( Matrix )

    ! Input parameters

    TYPE (Matrix_t) :: Matrix

    ! Local parameters

    INTEGER :: i, j, k, l
    DOUBLE PRECISION :: tl
    PARAMETER ( tl = 1.0d-15 )
  
    !*********************************************************************

    ! Initialize the ILUValues

    DO i = 1, SIZE( Matrix % Values )
       Matrix % ILUValues(i) = Matrix % Values(i)
    END DO

    !
    ! This is from Saads book, Algorithm 10.4
    !

    DO i = 2, Matrix % NumberOfRows

       DO k = Matrix % Rows(i), Matrix % Diag(i) - 1

          ! Check for small pivot

          IF ( ABS(Matrix % ILUValues( Matrix % Diag( Matrix % Cols(k) ))) &
               < tl ) THEN
             PRINT *, 'Small pivot : ', &
                  Matrix % ILUValues( Matrix % Diag( Matrix % Cols(k) ))
          END IF

          ! Compute a_ik = a_ik / a_kk
          
          Matrix % ILUValues(k) = Matrix % ILUValues (k) &
               / Matrix % ILUValues(Matrix % Diag( Matrix % Cols(k)))

          DO j = k + 1, Matrix % Rows(i+1) - 1

             ! Compute a_ij = a_ij - a_ik * a_kj

             DO l = Matrix % Rows(Matrix % Cols(k)), &
                  Matrix % Rows(Matrix % Cols(k) + 1) - 1

                IF (Matrix % Cols(l) == Matrix % Cols(j) ) THEN
                   Matrix % ILUValues(j) = Matrix % ILUValues(j) - &
                        Matrix % ILUValues(k) * Matrix % ILUValues(l)
                   EXIT
                END IF

             END DO

          END DO
          
       END DO

    END DO

    DO i = 1, Matrix % NumberOfRows
       Matrix % ILUValues(Matrix % Diag(i)) = 1.0 / &
            Matrix % ILUValues(Matrix % Diag(i))
    END DO

  END SUBROUTINE ParILU0
  
END MODULE SParIterPrecond

!> \{
