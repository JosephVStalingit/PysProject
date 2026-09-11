# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_tfqmr.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_tfqmr.F90"
module huti_tfqmr
  use huti_aux
  implicit none
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
  ! Subroutines to implement Transpose Free QMR iteration
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

# 32 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_tfqmr.F90" 2

  !*************************************************************************
  !*************************************************************************
  !
  ! These subroutines are based on a paper by Roland W. Freund:
  ! "A Transpose-Free Quasi-Minimal Residual Algorithm for Non-Hermitian
  !  Linear Systems", 1993 (SIAM J. Sci. Comput, March 1993)
  !
  ! All matrix-vector operations are done externally, so we do not need
  ! to know about the matrix structure (sparse or dense). Memory allocation
  ! for the working arrays has also been done externally.

  !*************************************************************************
  ! Work array is used in the following order:
  ! work(:,1) = v
  ! work(:,2) = y
  ! work(:,3) = y new
  ! work(:,4) = r tilde (zero)
  ! work(:,5) = t1v (temporary for matrix-vector operations)
  ! work(:,6) = t2v (temporary for matrix-vector operations)
  ! work(:,7) = w
  ! work(:,8) = d
  ! work(:,9) = r
  ! work(:,10) = trv (temporary vector for residual computations)
  !
  !*************************************************************************
  ! Definitions to make the code more understandable and to make it look
  ! like the pseudo code
  !



# 84 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_tfqmr.F90"

  ! This is the magic ratio for upperb and tolerance used in upper bound
  ! convergence test


contains

  !*************************************************************************
  !*************************************************************************
  ! Single precision version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_stfqmrsolv  ( ndim, wrkdim, xvec, rhsvec, ipar,&
       dpar, work, matvecsubr, pcondlsubr, pcondrsubr, &
       dotprodfun, normfun, stopcfun )

    use huti_interfaces
    implicit none

    procedure( mv_iface_s ), pointer :: matvecsubr
    procedure( pc_iface_s ), pointer :: pcondlsubr
    procedure( pc_iface_s ), pointer :: pcondrsubr
    procedure( dotp_iface_s ), pointer :: dotprodfun
    procedure( norm_iface_s ), pointer :: normfun
    procedure( stopc_iface_s ), pointer :: stopcfun

    ! Parameters

    integer :: ndim, wrkdim
    real, dimension(ndim) :: xvec, rhsvec
    integer, dimension(50) :: ipar
    double precision, dimension(10) :: dpar
    real, dimension(ndim,wrkdim) :: work

    ! Local variables

    real :: rho, oldrho, eta, tau, gamma, oldgamma, alpha
    real :: beta, c
    integer :: iter_count

    real :: residual, upperb, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual TFQMR begins here (look the pseudo code in the
    ! "A Transpose-Free..."-paper, algorithm 5.1)
    !
    ! First the initialization part
    !

    iter_count = 1

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 .or. &
         ipar(12) .eq. 6 ) then
       rhsnorm = normfun( ipar(3), rhsvec, 1 )
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,8), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,8), 1 )
    end if

    !
    ! Part 1A - 1C
    !

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_srandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call pcondrsubr( work(:,8), xvec, ipar )
    call matvecsubr( work(:,8), work(:,9), ipar )
    work(:,8) = rhsvec - work(:,9)
    call pcondlsubr( work(:,9), work(:,8), ipar )

    work(:,2) = work(:,9); work(:,7) = work(:,9)
    call pcondrsubr( work(:,1), work(:,2), ipar )
    call matvecsubr( work(:,1), work(:,8), ipar )
    call pcondlsubr( work(:,1), work(:,8), ipar )
    work(:,6) = work(:,1)

    work(:,8) = 0
    tau = normfun( ipar(3), work(:,9), 1 )
    oldgamma = 0; gamma = 0; eta = 0

    work(:,4) = work(:,9)
    oldrho = dotprodfun ( ipar(3), work(:,4), 1, work(:,9), 1 )
    if ( oldrho .eq. 0 ) then
       ipar(30) = 30
       go to 1000
    end if

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !
    !
    ! Part 2A
    !

300 continue

    alpha = oldrho / dotprodfun( ipar(3), work(:,4), 1, work(:,1), 1 )
    work(:,3) = work(:,2) - alpha * work(:,1)

    !
    ! Part 2rhsvec
    !
    !
    ! This is the inner loop from 2n-1 to 2n
    !

    ! First the 2n-1 case

    ! Note: We have already MATRIX * work(:,2) in work(:,6)

    work(:,7) = work(:,7) - alpha * work(:,6)
    gamma = ( normfun( ipar(3), work(:,7), 1 )) / tau
    c = 1 / sqrt( 1 + gamma * gamma )
    tau = tau * gamma * c

    work(:,8) = work(:,2) + ((oldgamma * oldgamma * eta) / alpha) * work(:,8)
    eta = c * c * alpha
    xvec = xvec + eta * work(:,8)

    oldgamma = gamma

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    case (1)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 )
    case (3)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / precrhsnorm
    case (5)
       work(:,9) = eta * work(:,8)
       residual = normfun( ipar(3), work(:,9), 1 )
    case (6)
       upperb = real( sqrt( 2.0 * iter_count ) * tau / rhsnorm)
       if ( ( upperb / dpar(1) ) .lt. 10.0 ) then
          call pcondrsubr( work(:,10), xvec, ipar )
          call matvecsubr( work(:,10), work(:,9), ipar )
          work(:,10) = work(:,9) - rhsvec
          call pcondlsubr( work(:,9), work(:,10), ipar )
          residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
       else
          residual = upperb
       end if
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,9), ipar, dpar )
    case default
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    end select

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

    !
    ! And then the 2n case
    !

    call pcondrsubr( work(:,5), work(:,3), ipar )
    call matvecsubr( work(:,5), work(:,9), ipar )
    call pcondlsubr( work(:,5), work(:,9), ipar )

    work(:,7) = work(:,7) - alpha * work(:,5)
    gamma = ( normfun( ipar(3), work(:,7), 1 )) / tau
    c = 1 / sqrt( 1 + gamma * gamma )
    tau = tau * gamma * c

    work(:,8) = work(:,3) + ((oldgamma * oldgamma * eta) / alpha) * work(:,8)
    eta = c * c * alpha
    xvec = xvec + eta * work(:,8)

    oldgamma = gamma

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    case (1)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 )
    case (3)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), (/1/) )
       residual = normfun( ipar(3), work(:,10), 1 ) / precrhsnorm
    case (5)
       work(:,9) = eta * work(:,8)
       residual = normfun( ipar(3), work(:,9), 1 )
    case (6)
       upperb = real( sqrt( 2.0 * iter_count ) * tau / rhsnorm)
       if ( ( upperb / dpar(1) ) .lt. 10.0 ) then
          call pcondrsubr( work(:,10), xvec, ipar )
          call matvecsubr( work(:,10), work(:,9), ipar )
          work(:,10) = work(:,9) - rhsvec
          call pcondlsubr( work(:,9), work(:,10), ipar )
          residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
       else
          residual = upperb
       end if
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,9), ipar, dpar )
    case default
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    end select

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

    !
    ! Produce debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          if ( ipar(12) .eq. 6 ) then
             write (*, '(I8, 2E17.7)') iter_count, residual, upperb
          else
             write (*, '(I8, E17.7)') iter_count, residual
          end if
       end if
    end if

    !
    ! Part 2C
    !

    rho = dotprodfun( ipar(3), work(:,4), 1, work(:,7), 1 )
    beta = rho / oldrho
    work(:,3) = work(:,7) + beta * work(:,3)
    call pcondrsubr( work(:,6), work(:,3), ipar )
    call matvecsubr( work(:,6), work(:,9), ipar )
    call pcondlsubr( work(:,6), work(:,9), ipar )

    ! Note: we still have MATRIX * work(:,3) in work(:,5)

    work(:,1) = work(:,6) + beta * work(:,5) + beta * beta * work(:,1)
    work(:,2) = work(:,3)

    oldrho = rho

    !
    ! Return next time back to the iteration loop (without initialization)
    !

    iter_count = iter_count + 1
    if ( iter_count .gt. ipar(10) ) then
       ipar(30) = 2
       go to 1000
    end if

    go to 300

    !
    ! This is where we exit last time (after enough iterations or breakdown)
    !

1000 continue

    ! Compute the unpreconditioned xvec

    call pcondrsubr( work(:,10), xvec, ipar )
    xvec = work(:,10)

    if ( ipar(5) .ne. 0 ) then
       if ( ipar(12) .eq. 6 ) then
          write (*, '(I8, 2E17.7)') iter_count, residual, upperb
       else
          write (*, '(I8, E17.7)') iter_count, residual
       end if
    end if
    ipar(31) = iter_count

    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_stfqmrsolv

  !*************************************************************************

  !*************************************************************************
  !*************************************************************************
  ! Double precision version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_dtfqmrsolv  ( ndim, wrkdim, xvec, rhsvec, ipar,&
       dpar, work, matvecsubr, pcondlsubr, pcondrsubr, &
       dotprodfun, normfun, stopcfun )

    use huti_interfaces
    implicit none

    procedure( mv_iface_d ), pointer :: matvecsubr
    procedure( pc_iface_d ), pointer :: pcondlsubr
    procedure( pc_iface_d ), pointer :: pcondrsubr
    procedure( dotp_iface_d ), pointer :: dotprodfun
    procedure( norm_iface_d ), pointer :: normfun
    procedure( stopc_iface_d ), pointer :: stopcfun

    ! Parameters

    integer :: ndim, wrkdim
    double precision, dimension(ndim) :: xvec, rhsvec
    integer, dimension(50) :: ipar
    double precision, dimension(10) :: dpar
    double precision, dimension(ndim,wrkdim) :: work

    ! Local variables

    double precision :: rho, oldrho, eta, tau, gamma, oldgamma, alpha
    double precision :: beta, c
    integer :: iter_count

    double precision :: residual, upperb, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual TFQMR begins here (look the pseudo code in the
    ! "A Transpose-Free..."-paper, algorithm 5.1)
    !
    ! First the initialization part
    !

    iter_count = 1

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 .or. &
         ipar(12) .eq. 6 ) then
       rhsnorm = normfun( ipar(3), rhsvec, 1 )
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,8), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,8), 1 )
    end if

    !
    ! Part 1A - 1C
    !

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_drandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call pcondrsubr( work(:,8), xvec, ipar )
    call matvecsubr( work(:,8), work(:,9), ipar )
    work(:,8) = rhsvec - work(:,9)
    call pcondlsubr( work(:,9), work(:,8), ipar )

    work(:,2) = work(:,9); work(:,7) = work(:,9)
    call pcondrsubr( work(:,1), work(:,2), ipar )
    call matvecsubr( work(:,1), work(:,8), ipar )
    call pcondlsubr( work(:,1), work(:,8), ipar )
    work(:,6) = work(:,1)

    work(:,8) = 0
    tau = normfun( ipar(3), work(:,9), 1 )
    oldgamma = 0; gamma = 0; eta = 0

    work(:,4) = work(:,9)
    oldrho = dotprodfun ( ipar(3), work(:,4), 1, work(:,9), 1 )
    if ( oldrho .eq. 0 ) then
       ipar(30) = 30
       go to 1000
    end if

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !
    !
    ! Part 2A
    !

300 continue

    alpha = oldrho / dotprodfun( ipar(3), work(:,4), 1, work(:,1), 1 )
    work(:,3) = work(:,2) - alpha * work(:,1)

    !
    ! Part 2rhsvec
    !
    !
    ! This is the inner loop from 2n-1 to 2n
    !

    ! First the 2n-1 case

    ! Note: We have already MATRIX * work(:,2) in work(:,6)

    work(:,7) = work(:,7) - alpha * work(:,6)
    gamma = ( normfun( ipar(3), work(:,7), 1 )) / tau
    c = 1 / sqrt( 1 + gamma * gamma )
    tau = tau * gamma * c

    work(:,8) = work(:,2) + ((oldgamma * oldgamma * eta) / alpha) * work(:,8)
    eta = c * c * alpha
    xvec = xvec + eta * work(:,8)

    oldgamma = gamma

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    case (1)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 )
    case (3)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / precrhsnorm
    case (5)
       work(:,9) = eta * work(:,8)
       residual = normfun( ipar(3), work(:,9), 1 )
    case (6)
       upperb = real( sqrt( 2.0 * iter_count ) * tau / rhsnorm)
       if ( ( upperb / dpar(1) ) .lt. 10.0 ) then
          call pcondrsubr( work(:,10), xvec, ipar )
          call matvecsubr( work(:,10), work(:,9), ipar )
          work(:,10) = work(:,9) - rhsvec
          call pcondlsubr( work(:,9), work(:,10), ipar )
          residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
       else
          residual = upperb
       end if
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,9), ipar, dpar )
    case default
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    end select

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

    !
    ! And then the 2n case
    !

    call pcondrsubr( work(:,5), work(:,3), ipar )
    call matvecsubr( work(:,5), work(:,9), ipar )
    call pcondlsubr( work(:,5), work(:,9), ipar )

    work(:,7) = work(:,7) - alpha * work(:,5)
    gamma = ( normfun( ipar(3), work(:,7), 1 )) / tau
    c = 1 / sqrt( 1 + gamma * gamma )
    tau = tau * gamma * c

    work(:,8) = work(:,3) + ((oldgamma * oldgamma * eta) / alpha) * work(:,8)
    eta = c * c * alpha
    xvec = xvec + eta * work(:,8)

    oldgamma = gamma

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    case (1)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 )
    case (3)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), (/1/) )
       residual = normfun( ipar(3), work(:,10), 1 ) / precrhsnorm
    case (5)
       work(:,9) = eta * work(:,8)
       residual = normfun( ipar(3), work(:,9), 1 )
    case (6)
       upperb = real( sqrt( 2.0 * iter_count ) * tau / rhsnorm)
       if ( ( upperb / dpar(1) ) .lt. 10.0 ) then
          call pcondrsubr( work(:,10), xvec, ipar )
          call matvecsubr( work(:,10), work(:,9), ipar )
          work(:,10) = work(:,9) - rhsvec
          call pcondlsubr( work(:,9), work(:,10), ipar )
          residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
       else
          residual = upperb
       end if
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,9), ipar, dpar )
    case default
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    end select

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

    !
    ! Produce debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          if ( ipar(12) .eq. 6 ) then
             write (*, '(I8, 2E17.7)') iter_count, residual, upperb
          else
             write (*, '(I8, E17.7)') iter_count, residual
          end if
       end if
    end if

    !
    ! Part 2C
    !

    rho = dotprodfun( ipar(3), work(:,4), 1, work(:,7), 1 )
    beta = rho / oldrho
    work(:,3) = work(:,7) + beta * work(:,3)
    call pcondrsubr( work(:,6), work(:,3), ipar )
    call matvecsubr( work(:,6), work(:,9), ipar )
    call pcondlsubr( work(:,6), work(:,9), ipar )

    ! Note: we still have MATRIX * work(:,3) in work(:,5)

    work(:,1) = work(:,6) + beta * work(:,5) + beta * beta * work(:,1)
    work(:,2) = work(:,3)

    oldrho = rho

    !
    ! Return next time back to the iteration loop (without initialization)
    !

    iter_count = iter_count + 1
    if ( iter_count .gt. ipar(10) ) then
       ipar(30) = 2
       go to 1000
    end if

    go to 300

    !
    ! This is where we exit last time (after enough iterations or breakdown)
    !

1000 continue

    ! Compute the unpreconditioned xvec

    call pcondrsubr( work(:,10), xvec, ipar )
    xvec = work(:,10)

    if ( ipar(5) .ne. 0 ) then
       if ( ipar(12) .eq. 6 ) then
          write (*, '(I8, 2E17.7)') iter_count, residual, upperb
       else
          write (*, '(I8, E17.7)') iter_count, residual
       end if
    end if
    ipar(31) = iter_count

    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_dtfqmrsolv

  !*************************************************************************

  !*************************************************************************
  !*************************************************************************
  ! Complex version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_ctfqmrsolv  ( ndim, wrkdim, xvec, rhsvec, ipar,&
       dpar, work, matvecsubr, pcondlsubr, pcondrsubr, &
       dotprodfun, normfun, stopcfun )

    use huti_interfaces
    implicit none

    procedure( mv_iface_c ), pointer :: matvecsubr
    procedure( pc_iface_c ), pointer :: pcondlsubr
    procedure( pc_iface_c ), pointer :: pcondrsubr
    procedure( dotp_iface_c ), pointer :: dotprodfun
    procedure( norm_iface_c ), pointer :: normfun
    procedure( stopc_iface_c ), pointer :: stopcfun

    ! Parameters

    integer :: ndim, wrkdim
    complex, dimension(ndim) :: xvec, rhsvec
    integer, dimension(50) :: ipar
    double precision, dimension(10) :: dpar
    complex, dimension(ndim,wrkdim) :: work

    ! Local variables

    complex :: rho, oldrho, eta, tau, gamma, oldgamma, alpha
    complex :: beta, c
    integer :: iter_count

    real :: residual, upperb, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual TFQMR begins here (look the pseudo code in the
    ! "A Transpose-Free..."-paper, algorithm 5.1)
    !
    ! First the initialization part
    !

    iter_count = 1

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 .or. &
         ipar(12) .eq. 6 ) then
       rhsnorm = normfun( ipar(3), rhsvec, 1 )
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,8), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,8), 1 )
    end if

    !
    ! Part 1A - 1C
    !

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_crandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call pcondrsubr( work(:,8), xvec, ipar )
    call matvecsubr( work(:,8), work(:,9), ipar )
    work(:,8) = rhsvec - work(:,9)
    call pcondlsubr( work(:,9), work(:,8), ipar )

    work(:,2) = work(:,9); work(:,7) = work(:,9)
    call pcondrsubr( work(:,1), work(:,2), ipar )
    call matvecsubr( work(:,1), work(:,8), ipar )
    call pcondlsubr( work(:,1), work(:,8), ipar )
    work(:,6) = work(:,1)

    work(:,8) = 0
    tau = normfun( ipar(3), work(:,9), 1 )
    oldgamma = 0; gamma = 0; eta = 0

    work(:,4) = work(:,9)
    oldrho = dotprodfun ( ipar(3), work(:,4), 1, work(:,9), 1 )
    if ( oldrho .eq. 0 ) then
       ipar(30) = 30
       go to 1000
    end if

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !
    !
    ! Part 2A
    !

300 continue

    alpha = oldrho / dotprodfun( ipar(3), work(:,4), 1, work(:,1), 1 )
    work(:,3) = work(:,2) - alpha * work(:,1)

    !
    ! Part 2rhsvec
    !
    !
    ! This is the inner loop from 2n-1 to 2n
    !

    ! First the 2n-1 case

    ! Note: We have already MATRIX * work(:,2) in work(:,6)

    work(:,7) = work(:,7) - alpha * work(:,6)
    gamma = ( normfun( ipar(3), work(:,7), 1 )) / tau
    c = 1 / sqrt( 1 + gamma * gamma )
    tau = tau * gamma * c

    work(:,8) = work(:,2) + ((oldgamma * oldgamma * eta) / alpha) * work(:,8)
    eta = c * c * alpha
    xvec = xvec + eta * work(:,8)

    oldgamma = gamma

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    case (1)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 )
    case (3)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / precrhsnorm
    case (5)
       work(:,9) = eta * work(:,8)
       residual = normfun( ipar(3), work(:,9), 1 )
    case (6)
       upperb = real( sqrt( 2.0 * iter_count ) * tau / rhsnorm)
       if ( ( upperb / dpar(1) ) .lt. 10.0 ) then
          call pcondrsubr( work(:,10), xvec, ipar )
          call matvecsubr( work(:,10), work(:,9), ipar )
          work(:,10) = work(:,9) - rhsvec
          call pcondlsubr( work(:,9), work(:,10), ipar )
          residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
       else
          residual = upperb
       end if
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,9), ipar, dpar )
    case default
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    end select

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

    !
    ! And then the 2n case
    !

    call pcondrsubr( work(:,5), work(:,3), ipar )
    call matvecsubr( work(:,5), work(:,9), ipar )
    call pcondlsubr( work(:,5), work(:,9), ipar )

    work(:,7) = work(:,7) - alpha * work(:,5)
    gamma = ( normfun( ipar(3), work(:,7), 1 )) / tau
    c = 1 / sqrt( 1 + gamma * gamma )
    tau = tau * gamma * c

    work(:,8) = work(:,3) + ((oldgamma * oldgamma * eta) / alpha) * work(:,8)
    eta = c * c * alpha
    xvec = xvec + eta * work(:,8)

    oldgamma = gamma

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    case (1)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 )
    case (3)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), (/1/) )
       residual = normfun( ipar(3), work(:,10), 1 ) / precrhsnorm
    case (5)
       work(:,9) = eta * work(:,8)
       residual = normfun( ipar(3), work(:,9), 1 )
    case (6)
       upperb = real( sqrt( 2.0 * iter_count ) * tau / rhsnorm)
       if ( ( upperb / dpar(1) ) .lt. 10.0 ) then
          call pcondrsubr( work(:,10), xvec, ipar )
          call matvecsubr( work(:,10), work(:,9), ipar )
          work(:,10) = work(:,9) - rhsvec
          call pcondlsubr( work(:,9), work(:,10), ipar )
          residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
       else
          residual = upperb
       end if
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,9), ipar, dpar )
    case default
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    end select

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

    !
    ! Produce debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          if ( ipar(12) .eq. 6 ) then
             write (*, '(I8, 2E17.7)') iter_count, residual, upperb
          else
             write (*, '(I8, E17.7)') iter_count, residual
          end if
       end if
    end if

    !
    ! Part 2C
    !

    rho = dotprodfun( ipar(3), work(:,4), 1, work(:,7), 1 )
    beta = rho / oldrho
    work(:,3) = work(:,7) + beta * work(:,3)
    call pcondrsubr( work(:,6), work(:,3), ipar )
    call matvecsubr( work(:,6), work(:,9), ipar )
    call pcondlsubr( work(:,6), work(:,9), ipar )

    ! Note: we still have MATRIX * work(:,3) in work(:,5)

    work(:,1) = work(:,6) + beta * work(:,5) + beta * beta * work(:,1)
    work(:,2) = work(:,3)

    oldrho = rho

    !
    ! Return next time back to the iteration loop (without initialization)
    !

    iter_count = iter_count + 1
    if ( iter_count .gt. ipar(10) ) then
       ipar(30) = 2
       go to 1000
    end if

    go to 300

    !
    ! This is where we exit last time (after enough iterations or breakdown)
    !

1000 continue

    ! Compute the unpreconditioned xvec

    call pcondrsubr( work(:,10), xvec, ipar )
    xvec = work(:,10)

    if ( ipar(5) .ne. 0 ) then
       if ( ipar(12) .eq. 6 ) then
          write (*, '(I8, 2E17.7)') iter_count, residual, upperb
       else
          write (*, '(I8, E17.7)') iter_count, residual
       end if
    end if
    ipar(31) = iter_count

    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_ctfqmrsolv

  !*************************************************************************

  !*************************************************************************
  !*************************************************************************
  ! Double complex version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_ztfqmrsolv  ( ndim, wrkdim, xvec, rhsvec, ipar,&
       dpar, work, matvecsubr, pcondlsubr, pcondrsubr, &
       dotprodfun, normfun, stopcfun )

    use huti_interfaces
    implicit none

    procedure( mv_iface_z ), pointer :: matvecsubr
    procedure( pc_iface_z ), pointer :: pcondlsubr
    procedure( pc_iface_z ), pointer :: pcondrsubr
    procedure( dotp_iface_z ), pointer :: dotprodfun
    procedure( norm_iface_z ), pointer :: normfun
    procedure( stopc_iface_z ), pointer :: stopcfun

    ! Parameters

    integer :: ndim, wrkdim
    double complex, dimension(ndim) :: xvec, rhsvec
    integer, dimension(50) :: ipar
    double precision, dimension(10) :: dpar
    double complex, dimension(ndim,wrkdim) :: work

    ! Local variables

    double complex :: rho, oldrho, eta, tau, gamma, oldgamma, alpha
    double complex :: beta, c
    integer :: iter_count

    double precision :: residual, upperb, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual TFQMR begins here (look the pseudo code in the
    ! "A Transpose-Free..."-paper, algorithm 5.1)
    !
    ! First the initialization part
    !

    iter_count = 1

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 .or. &
         ipar(12) .eq. 6 ) then
       rhsnorm = normfun( ipar(3), rhsvec, 1 )
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,8), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,8), 1 )
    end if

    !
    ! Part 1A - 1C
    !

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_zrandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call pcondrsubr( work(:,8), xvec, ipar )
    call matvecsubr( work(:,8), work(:,9), ipar )
    work(:,8) = rhsvec - work(:,9)
    call pcondlsubr( work(:,9), work(:,8), ipar )

    work(:,2) = work(:,9); work(:,7) = work(:,9)
    call pcondrsubr( work(:,1), work(:,2), ipar )
    call matvecsubr( work(:,1), work(:,8), ipar )
    call pcondlsubr( work(:,1), work(:,8), ipar )
    work(:,6) = work(:,1)

    work(:,8) = 0
    tau = normfun( ipar(3), work(:,9), 1 )
    oldgamma = 0; gamma = 0; eta = 0

    work(:,4) = work(:,9)
    oldrho = dotprodfun ( ipar(3), work(:,4), 1, work(:,9), 1 )
    if ( oldrho .eq. 0 ) then
       ipar(30) = 30
       go to 1000
    end if

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !
    !
    ! Part 2A
    !

300 continue

    alpha = oldrho / dotprodfun( ipar(3), work(:,4), 1, work(:,1), 1 )
    work(:,3) = work(:,2) - alpha * work(:,1)

    !
    ! Part 2rhsvec
    !
    !
    ! This is the inner loop from 2n-1 to 2n
    !

    ! First the 2n-1 case

    ! Note: We have already MATRIX * work(:,2) in work(:,6)

    work(:,7) = work(:,7) - alpha * work(:,6)
    gamma = ( normfun( ipar(3), work(:,7), 1 )) / tau
    c = 1 / sqrt( 1 + gamma * gamma )
    tau = tau * gamma * c

    work(:,8) = work(:,2) + ((oldgamma * oldgamma * eta) / alpha) * work(:,8)
    eta = c * c * alpha
    xvec = xvec + eta * work(:,8)

    oldgamma = gamma

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    case (1)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 )
    case (3)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / precrhsnorm
    case (5)
       work(:,9) = eta * work(:,8)
       residual = normfun( ipar(3), work(:,9), 1 )
    case (6)
       upperb = real( sqrt( 2.0 * iter_count ) * tau / rhsnorm)
       if ( ( upperb / dpar(1) ) .lt. 10.0 ) then
          call pcondrsubr( work(:,10), xvec, ipar )
          call matvecsubr( work(:,10), work(:,9), ipar )
          work(:,10) = work(:,9) - rhsvec
          call pcondlsubr( work(:,9), work(:,10), ipar )
          residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
       else
          residual = upperb
       end if
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,9), ipar, dpar )
    case default
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    end select

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

    !
    ! And then the 2n case
    !

    call pcondrsubr( work(:,5), work(:,3), ipar )
    call matvecsubr( work(:,5), work(:,9), ipar )
    call pcondlsubr( work(:,5), work(:,9), ipar )

    work(:,7) = work(:,7) - alpha * work(:,5)
    gamma = ( normfun( ipar(3), work(:,7), 1 )) / tau
    c = 1 / sqrt( 1 + gamma * gamma )
    tau = tau * gamma * c

    work(:,8) = work(:,3) + ((oldgamma * oldgamma * eta) / alpha) * work(:,8)
    eta = c * c * alpha
    xvec = xvec + eta * work(:,8)

    oldgamma = gamma

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    case (1)
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 )
    case (3)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), ipar )
       residual = normfun( ipar(3), work(:,10), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,9), ipar )
       work(:,9) = work(:,9) - rhsvec
       call pcondlsubr( work(:,10), work(:,9), (/1/) )
       residual = normfun( ipar(3), work(:,10), 1 ) / precrhsnorm
    case (5)
       work(:,9) = eta * work(:,8)
       residual = normfun( ipar(3), work(:,9), 1 )
    case (6)
       upperb = real( sqrt( 2.0 * iter_count ) * tau / rhsnorm)
       if ( ( upperb / dpar(1) ) .lt. 10.0 ) then
          call pcondrsubr( work(:,10), xvec, ipar )
          call matvecsubr( work(:,10), work(:,9), ipar )
          work(:,10) = work(:,9) - rhsvec
          call pcondlsubr( work(:,9), work(:,10), ipar )
          residual = normfun( ipar(3), work(:,9), 1 ) / rhsnorm
       else
          residual = upperb
       end if
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,9), ipar, dpar )
    case default
       call pcondrsubr( work(:,10), xvec, ipar )
       call matvecsubr( work(:,10), work(:,9), ipar )
       work(:,10) = work(:,9) - rhsvec
       call pcondlsubr( work(:,9), work(:,10), ipar )
       residual = normfun( ipar(3), work(:,9), 1 )
    end select

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

    !
    ! Produce debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          if ( ipar(12) .eq. 6 ) then
             write (*, '(I8, 2E17.7)') iter_count, residual, upperb
          else
             write (*, '(I8, E17.7)') iter_count, residual
          end if
       end if
    end if

    !
    ! Part 2C
    !

    rho = dotprodfun( ipar(3), work(:,4), 1, work(:,7), 1 )
    beta = rho / oldrho
    work(:,3) = work(:,7) + beta * work(:,3)
    call pcondrsubr( work(:,6), work(:,3), ipar )
    call matvecsubr( work(:,6), work(:,9), ipar )
    call pcondlsubr( work(:,6), work(:,9), ipar )

    ! Note: we still have MATRIX * work(:,3) in work(:,5)

    work(:,1) = work(:,6) + beta * work(:,5) + beta * beta * work(:,1)
    work(:,2) = work(:,3)

    oldrho = rho

    !
    ! Return next time back to the iteration loop (without initialization)
    !

    iter_count = iter_count + 1
    if ( iter_count .gt. ipar(10) ) then
       ipar(30) = 2
       go to 1000
    end if

    go to 300

    !
    ! This is where we exit last time (after enough iterations or breakdown)
    !

1000 continue

    ! Compute the unpreconditioned xvec

    call pcondrsubr( work(:,10), xvec, ipar )
    xvec = work(:,10)

    if ( ipar(5) .ne. 0 ) then
       if ( ipar(12) .eq. 6 ) then
          write (*, '(I8, 2E17.7)') iter_count, residual, upperb
       else
          write (*, '(I8, E17.7)') iter_count, residual
       end if
    end if
    ipar(31) = iter_count

    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_ztfqmrsolv

  !*************************************************************************

end module huti_tfqmr
