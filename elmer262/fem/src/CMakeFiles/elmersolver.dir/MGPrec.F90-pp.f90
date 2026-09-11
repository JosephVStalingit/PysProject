# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MGPrec.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MGPrec.F90"
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

# 25 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MGPrec.F90" 2

!> \ingroup ElmerLib
!------------------------------------------------------------------------------
  SUBROUTINE MultigridPrec( u,v,ipar )
!------------------------------------------------------------------------------
    USE Multigrid

    INTEGER, DIMENSION(*) :: ipar  !< structure holding info from (HUTIter-iterative solver package)
    REAL(KIND=dp), TARGET :: u(*)
    REAL(KIND=dp), TARGET :: v(*)

    INTEGER :: i,j,k,me,n, DOFs
    TYPE(Solver_t), POINTER :: PSolver

    TYPE(Matrix_t), POINTER :: A
    REAL(KIND=dp), POINTER  :: x(:),b(:)

    CALL Info('MultigridPrec','Starting Multigrid preconditioning cycle',Level=12)

    PSolver => CurrentModel % Solver

    n = ipar(3)
    IF ( PSolver % Matrix % COMPLEX ) n=2*n

    x => u(1:n)
    b => v(1:n)
    A => GlobalMatrix

    IF ( ParEnv % PEs > 1 ) THEN
      A => GlobalMatrix % EMatrix
      n = A % NumberOfRows
      ALLOCATE( x(n), b(n) )
      x=0; b=0;

      j = 0
      me = ParEnv % MyPe
      DO i=1,n
        IF ( A % ParallelInfo % NeighbourList(i) % Neighbours(1) == me ) THEN
           j = j + 1
           b(i) = v(j)
        END IF
      END DO
    END IF

    DOFs =  PSolver % Variable % DOFs
    x = b
    CALL MultiGridSolve( A, x, b, &
          DOFs,  PSolver, PSolver % MultiGridLevel, FirstCall(stack_pos))

    IF ( ParEnv % PEs > 1 ) THEN
      j = 0
      DO i=1,n
        IF ( A % ParallelInfo % NeighbourList(i) % Neighbours(1) == me ) THEN
           j = j + 1
           u(j) = x(i)
        END IF
      END DO
      DEALLOCATE( x,b )
    END IF

    FirstCall(stack_pos) = .FALSE.

    CALL Info('MultigridPrec','Done multigrid preconditioning cycle',Level=12)

  END SUBROUTINE MultigridPrec
!------------------------------------------------------------------------------
