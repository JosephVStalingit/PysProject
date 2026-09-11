# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_cgs.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_cgs.F90"
module huti_cgs
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
  ! Subroutines to implement Conjugate Gradient Squared iteration


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

# 31 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_cgs.F90" 2

  !*************************************************************************
  !*************************************************************************
  !
  ! This subroutine is based on a book by Barret et al.:
  ! "Templates for the Solution of Linear Systems: Building Blocks for
  !  Iterative Methods", 1993.
  !
  ! All matrix-vector operations are done externally, so we do not need
  ! to know about the matrix structure (sparse or dense). Memory allocation
  ! for the working arrays has also been done externally.

  !*************************************************************************
  ! Work array is used in the following order:
  ! work(:,1) = r tilde (zero)
  ! work(:,2) = p
  ! work(:,3) = q
  ! work(:,4) = u
  ! work(:,5) = t1v (temporary)
  ! work(:,6) = t2v (temporary)
  ! work(:,7) = r
  !
  !*************************************************************************
  ! Definitions to make the code more understandable and to make it look
  ! like the pseudo code
  !




# 75 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_cgs.F90"

contains


  !*************************************************************************
  !*************************************************************************
  ! Single precision version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_scgssolv  ( ndim, wrkdim, xvec, rhsvec, ipar,&
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

    real :: rho, oldrho, alpha, beta
    integer :: iter_count

    real :: residual, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual CGS begins here (look the pseudo code in the
    ! "Templates..."-book, page 26)
    !
    ! First the initialization part
    !

    iter_count = 1

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 ) then
       rhsnorm = normfun( ipar(3), rhsvec, 1 )
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,2), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,2), 1 )
    end if

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_srandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call matvecsubr( xvec, work(:,7), ipar )
    work(:,7) = rhsvec - work(:,7)
    work(:,1) = work(:,7)

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    rho = dotprodfun( ipar(3), work(:,1), 1, work(:,7), 1 )
    if ( rho .eq. 0 ) then
       ipar(30) = 25
       go to 1000
    end if

    if ( iter_count .eq. 1 ) then
       work(:,4) = work(:,7)
       work(:,2) = work(:,4)
    else
       beta = rho / oldrho
       work(:,4) = work(:,7) + beta * work(:,3)
       work(:,2) = work(:,4) + beta * work(:,3) + beta * beta * work(:,2)
    end if

    call pcondlsubr( work(:,6), work(:,2), ipar )
    call pcondrsubr( work(:,5), work(:,6), ipar )

    call matvecsubr( work(:,5), work(:,6), ipar )

    alpha = rho / dotprodfun( ipar(3), work(:,1), 1, work(:,6), 1 )
    work(:,3) = work(:,4) - alpha * work(:,6)

    work(:,6) = work(:,4) + work(:,3)

    call pcondlsubr( work(:,4), work(:,6), ipar )
    call pcondrsubr( work(:,5), work(:,4), ipar )
    xvec = xvec + alpha * work(:,5)

    call matvecsubr( work(:,5), work(:,6), ipar )
    work(:,7) = work(:,7) - alpha * work(:,6)

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 )
    case (1)
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 ) / rhsnorm
    case (2)
       residual = normfun( ipar(3), work(:,7), 1 )
    case (3)
       residual = normfun( ipar(3), work(:,7), 1 ) / rhsnorm
    case (4)
       residual = normfun( ipar(3), work(:,7), 1 ) / precrhsnorm
    case (5)
       work(:,5) = alpha * work(:,5)
       residual = normfun( ipar(3), work(:,5), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,7), ipar, dpar )
    case default
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 )
    end select

    !
    ! Print debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          write (*, '(I8, E11.4)') iter_count, residual
       end if
    end if

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

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
    if ( ipar(5) .ne. 0 ) then
       write (*, '(I8, E11.4)') iter_count, residual
    end if

    ipar(31) = iter_count
    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_scgssolv

  !*************************************************************************


  !*************************************************************************
  !*************************************************************************
  ! Double precision version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_dcgssolv  ( ndim, wrkdim, xvec, rhsvec, ipar,&
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

    double precision :: rho, oldrho, alpha, beta
    integer :: iter_count

    double precision :: residual, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual CGS begins here (look the pseudo code in the
    ! "Templates..."-book, page 26)
    !
    ! First the initialization part
    !

    iter_count = 1

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 ) then
       rhsnorm = normfun( ipar(3), rhsvec, 1 )
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,2), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,2), 1 )
    end if

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_drandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call matvecsubr( xvec, work(:,7), ipar )
    work(:,7) = rhsvec - work(:,7)
    work(:,1) = work(:,7)

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    rho = dotprodfun( ipar(3), work(:,1), 1, work(:,7), 1 )
    if ( rho .eq. 0 ) then
       ipar(30) = 25
       go to 1000
    end if

    if ( iter_count .eq. 1 ) then
       work(:,4) = work(:,7)
       work(:,2) = work(:,4)
    else
       beta = rho / oldrho
       work(:,4) = work(:,7) + beta * work(:,3)
       work(:,2) = work(:,4) + beta * work(:,3) + beta * beta * work(:,2)
    end if

    call pcondlsubr( work(:,6), work(:,2), ipar )
    call pcondrsubr( work(:,5), work(:,6), ipar )

    call matvecsubr( work(:,5), work(:,6), ipar )

    alpha = rho / dotprodfun( ipar(3), work(:,1), 1, work(:,6), 1 )
    work(:,3) = work(:,4) - alpha * work(:,6)

    work(:,6) = work(:,4) + work(:,3)

    call pcondlsubr( work(:,4), work(:,6), ipar )
    call pcondrsubr( work(:,5), work(:,4), ipar )
    xvec = xvec + alpha * work(:,5)

    call matvecsubr( work(:,5), work(:,6), ipar )
    work(:,7) = work(:,7) - alpha * work(:,6)

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 )
    case (1)
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 ) / rhsnorm
    case (2)
       residual = normfun( ipar(3), work(:,7), 1 )
    case (3)
       residual = normfun( ipar(3), work(:,7), 1 ) / rhsnorm
    case (4)
       residual = normfun( ipar(3), work(:,7), 1 ) / precrhsnorm
    case (5)
       work(:,5) = alpha * work(:,5)
       residual = normfun( ipar(3), work(:,5), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,7), ipar, dpar )
    case default
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 )
    end select

    !
    ! Print debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          write (*, '(I8, E11.4)') iter_count, residual
       end if
    end if

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF
    
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
    if ( ipar(5) .ne. 0 ) then
       write (*, '(I8, E11.4)') iter_count, residual
    end if

    ipar(31) = iter_count
    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_dcgssolv

  !*************************************************************************


  !*************************************************************************
  !*************************************************************************
  ! Complex version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_ccgssolv  ( ndim, wrkdim, xvec, rhsvec, ipar,&
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

    complex :: rho, oldrho, alpha, beta
    integer :: iter_count

    real :: residual, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual CGS begins here (look the pseudo code in the
    ! "Templates..."-book, page 26)
    !
    ! First the initialization part
    !

    iter_count = 1

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 ) then
       rhsnorm = normfun( ipar(3), rhsvec, 1 )
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,2), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,2), 1 )
    end if

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_crandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call matvecsubr( xvec, work(:,7), ipar )
    work(:,7) = rhsvec - work(:,7)
    work(:,1) = work(:,7)

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    rho = dotprodfun( ipar(3), work(:,1), 1, work(:,7), 1 )
    if ( rho .eq. 0 ) then
       ipar(30) = 25
       go to 1000
    end if

    if ( iter_count .eq. 1 ) then
       work(:,4) = work(:,7)
       work(:,2) = work(:,4)
    else
       beta = rho / oldrho
       work(:,4) = work(:,7) + beta * work(:,3)
       work(:,2) = work(:,4) + beta * work(:,3) + beta * beta * work(:,2)
    end if

    call pcondlsubr( work(:,6), work(:,2), ipar )
    call pcondrsubr( work(:,5), work(:,6), ipar )

    call matvecsubr( work(:,5), work(:,6), ipar )

    alpha = rho / dotprodfun( ipar(3), work(:,1), 1, work(:,6), 1 )
    work(:,3) = work(:,4) - alpha * work(:,6)

    work(:,6) = work(:,4) + work(:,3)

    call pcondlsubr( work(:,4), work(:,6), ipar )
    call pcondrsubr( work(:,5), work(:,4), ipar )
    xvec = xvec + alpha * work(:,5)

    call matvecsubr( work(:,5), work(:,6), ipar )
    work(:,7) = work(:,7) - alpha * work(:,6)

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 )
    case (1)
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 ) / rhsnorm
    case (2)
       residual = normfun( ipar(3), work(:,7), 1 )
    case (3)
       residual = normfun( ipar(3), work(:,7), 1 ) / rhsnorm
    case (4)
       residual = normfun( ipar(3), work(:,7), 1 ) / precrhsnorm
    case (5)
       work(:,5) = alpha * work(:,5)
       residual = normfun( ipar(3), work(:,5), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,7), ipar, dpar )
    case default
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 )
    end select

    !
    ! Print debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          write (*, '(I8, E11.4)') iter_count, residual
       end if
    end if

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

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
    if ( ipar(5) .ne. 0 ) then
       write (*, '(I8, E11.4)') iter_count, residual
    end if

    ipar(31) = iter_count
    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_ccgssolv

  !*************************************************************************


  !*************************************************************************
  !*************************************************************************
  ! Double complex version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_zcgssolv  ( ndim, wrkdim, xvec, rhsvec, ipar,&
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

    double complex :: rho, oldrho, alpha, beta
    integer :: iter_count

    double precision :: residual, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual CGS begins here (look the pseudo code in the
    ! "Templates..."-book, page 26)
    !
    ! First the initialization part
    !

    iter_count = 1

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 ) then
       rhsnorm = normfun( ipar(3), rhsvec, 1 )
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,2), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,2), 1 )
    end if

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_zrandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call matvecsubr( xvec, work(:,7), ipar )
    work(:,7) = rhsvec - work(:,7)
    work(:,1) = work(:,7)

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    rho = dotprodfun( ipar(3), work(:,1), 1, work(:,7), 1 )
    if ( rho .eq. 0 ) then
       ipar(30) = 25
       go to 1000
    end if

    if ( iter_count .eq. 1 ) then
       work(:,4) = work(:,7)
       work(:,2) = work(:,4)
    else
       beta = rho / oldrho
       work(:,4) = work(:,7) + beta * work(:,3)
       work(:,2) = work(:,4) + beta * work(:,3) + beta * beta * work(:,2)
    end if

    call pcondlsubr( work(:,6), work(:,2), ipar )
    call pcondrsubr( work(:,5), work(:,6), ipar )

    call matvecsubr( work(:,5), work(:,6), ipar )

    alpha = rho / dotprodfun( ipar(3), work(:,1), 1, work(:,6), 1 )
    work(:,3) = work(:,4) - alpha * work(:,6)

    work(:,6) = work(:,4) + work(:,3)

    call pcondlsubr( work(:,4), work(:,6), ipar )
    call pcondrsubr( work(:,5), work(:,4), ipar )
    xvec = xvec + alpha * work(:,5)

    call matvecsubr( work(:,5), work(:,6), ipar )
    work(:,7) = work(:,7) - alpha * work(:,6)

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 )
    case (1)
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 ) / rhsnorm
    case (2)
       residual = normfun( ipar(3), work(:,7), 1 )
    case (3)
       residual = normfun( ipar(3), work(:,7), 1 ) / rhsnorm
    case (4)
       residual = normfun( ipar(3), work(:,7), 1 ) / precrhsnorm
    case (5)
       work(:,5) = alpha * work(:,5)
       residual = normfun( ipar(3), work(:,5), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,7), ipar, dpar )
    case default
       call matvecsubr( xvec, work(:,5), ipar )
       work(:,5) = work(:,5) - rhsvec
       residual = normfun( ipar(3), work(:,5), 1 )
    end select

    !
    ! Print debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          write (*, '(I8, E11.4)') iter_count, residual
       end if
    end if

    if ( residual .lt. dpar(1) ) then
       ipar(30) = 1
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF

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
    if ( ipar(5) .ne. 0 ) then
       write (*, '(I8, E11.4)') iter_count, residual
    end if

    ipar(31) = iter_count
    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_zcgssolv

  !*************************************************************************


end module huti_cgs
