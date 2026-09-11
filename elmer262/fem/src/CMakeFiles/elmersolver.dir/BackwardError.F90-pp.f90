# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/BackwardError.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/BackwardError.F90"
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

# 26 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/BackwardError.F90" 2

!------------------------------------------------------------------------------
!> The normwise relative backward error err = ||b-Ax||/(||A|| ||x|| + ||b||) 
!> where ||.|| is the 2-norm
!------------------------------------------------------------------------------
FUNCTION NormwiseBackwardError2( x,b,r,ipar,dpar ) RESULT(err)
!------------------------------------------------------------------------------
  USE ParallelUtils

  INTEGER :: ipar(*),n
  DOUBLE PRECISION :: x(ipar(3)),b(ipar(3)),r(ipar(3)),dpar(*),err
  DOUBLE PRECISION :: res(ipar(3))

  n = ipar(3)

  IF(ParEnv % PEs>1) THEN
    CALL SParMatrixVector(x,res,ipar)
  ELSE
    CALL CRS_MatrixVectorMultiply(GlobalMatrix,x,res)
  END IF
  res = res - b(1:n)

  err = SQRT(ParallelReduction(SUM( res(1:n)**2) )) /  &
      SQRT(ParallelReduction(SUM(GlobalMatrix % Values**2))) * &
      SQRT(ParallelReduction(SUM(x(1:n)**2))) + &
      SQRT(ParallelReduction((SUM(b(1:n)**2))) )

!------------------------------------------------------------------------------
END FUNCTION NormwiseBackwardError2
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> The normwise relative backward error err = ||r||/(||A|| ||x|| + ||b||) 
!> where ||.|| is the supremum norm and A is assumed to be scaled such that its 
!> norm is the unity (setting Linear System Row Equilibration = Logical True).
!> Here the residual r = b - Ax should be known when calling this function.
!------------------------------------------------------------------------------
FUNCTION NormwiseBackwardError( x,b,r,ipar,dpar ) RESULT(err)
!------------------------------------------------------------------------------
  USE ParallelUtils

  INTEGER :: ipar(*),n
  DOUBLE PRECISION :: x(ipar(3)),b(ipar(3)),r(ipar(3)),dpar(*),err

  n = ipar(3)

  err = ParallelReduction(MAXVAL(ABS(r(1:n))),2) / &
      (ParallelReduction(MAXVAL(ABS(x(1:n))),2) + &
      ParallelReduction(MAXVAL(ABS(b(1:n))),2))

!------------------------------------------------------------------------------
END FUNCTION NormwiseBackwardError
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> The complex-valued version of the normwise relative backward error err =
!> ||r||/(||A|| ||x|| + ||b||) where ||.|| is the supremum norm and A is
!> assumed to be scaled such that its norm is the unity (setting Linear System
!> Row Equilibration = Logical True). Here the residual r = b - Ax should 
!> be known when calling this function.
!------------------------------------------------------------------------------
FUNCTION NormwiseBackwardError_Z( x,b,r,ipar,dpar ) RESULT(err)
!------------------------------------------------------------------------------
  USE ParallelUtils
  IMPLICIT NONE
  
  DOUBLE COMPLEX :: x(*),b(*),r(*)
  INTEGER :: ipar(*)
  DOUBLE PRECISION :: dpar(*)
  DOUBLE PRECISION :: err

  INTEGER :: n
  
!  n = ipar(3)
  n = ipar(3)
  
  err = ParallelReduction(MAXVAL(ABS(r(1:n))),2) / &
      (ParallelReduction(MAXVAL(ABS(x(1:n))),2)   + &
      ParallelReduction(MAXVAL(ABS(b(1:n))),2))
!------------------------------------------------------------------------------
END FUNCTION NormwiseBackwardError_Z
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> The normwise relative backward error err = ||b-Ax||/(||A|| ||x|| + ||b||) 
!> where ||.|| is the supremum norm. The matrix norm of A is computed within
!> this subroutine.
!------------------------------------------------------------------------------
FUNCTION NormwiseBackwardErrorGeneralized( x,b,r,ipar,dpar ) RESULT(err)
!------------------------------------------------------------------------------
  USE ParallelUtils

  INTEGER :: ipar(*),n
  DOUBLE PRECISION :: x(ipar(3)),b(ipar(3)),r(ipar(3)),dpar(*),err
  DOUBLE PRECISION :: res(ipar(3))
  DOUBLE PRECISION :: d(ipar(3)), ANorm

  n = ipar(3)

  d = 1.0d0
  res = 0.0d0
  IF(ParEnv % PEs>1) THEN
    CALL SParABSMatrixVector(d,res,ipar)
  ELSE
    CALL CRS_ABSMatrixVectorMultiply(GlobalMatrix,d,res)
  END IF
  ANorm = ParallelReduction(MAXVAL(ABS(res(1:n))),2)

  res = 0.0d0
  IF(ParEnv % PEs>1) THEN
    CALL SParMatrixVector(x,res,ipar)
  ELSE
    CALL CRS_MatrixVectorMultiply(GlobalMatrix,x,res)
  END IF
  res = res - b(1:n)

  err = ParallelReduction(MAXVAL(ABS(res(1:n))),2) / &
      (ANorm * ParallelReduction(MAXVAL(ABS(x(1:n))),2) + &
      ParallelReduction(MAXVAL(ABS(b(1:n))),2))

!------------------------------------------------------------------------------
END FUNCTION NormwiseBackwardErrorGeneralized
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> The componentwise relative backward error err = max_j{|r|_j /(|A| |x| + |b|)_j}
!> with r the residual r = b-Ax.
!------------------------------------------------------------------------------
FUNCTION ComponentwiseBackwardError( x,b,r,ipar,dpar ) RESULT(err)
!------------------------------------------------------------------------------
  USE ParallelUtils

  INTEGER :: ipar(*),n
  DOUBLE PRECISION :: x(ipar(3)),b(ipar(3)),r(ipar(3)),dpar(*),err
  DOUBLE PRECISION :: d(ipar(3)),res(ipar(3))    

  n = ipar(3)

  IF(ParEnv % PEs>1) THEN
    CALL SParMatrixVector(x,res,ipar)
  ELSE
    CALL CRS_MatrixVectorMultiply(GlobalMatrix,x,res)
  END IF
  res = res - b(1:n)
     
  IF(ParEnv % PEs>1) THEN
    CALL SParABSMatrixVector(ABS(x),d,ipar)
  ELSE
    CALL CRS_ABSMatrixVectorMultiply(GlobalMatrix,ABS(x),d)
  END IF
     
  d = d + ABS(b(1:n))

  err = 0.0d0
  DO i=1,n
    IF ( ABS(d(i)) < AEPS) THEN
      IF ( ABS(res(i)) > AEPS ) THEN
        err = HUGE(err)
        RETURN
      ELSE
        err = MAX(err,0.0d0)
      END IF
    ELSE
      err = MAX(err,ABS(res(i))/d(i))
    END IF
  END DO

  err = ParallelReduction(err,2)
!------------------------------------------------------------------------------
END FUNCTION ComponentwiseBackwardError
!------------------------------------------------------------------------------
