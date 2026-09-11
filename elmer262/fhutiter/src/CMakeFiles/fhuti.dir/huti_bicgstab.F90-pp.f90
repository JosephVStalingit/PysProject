# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_bicgstab.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_bicgstab.F90"
module huti_bicgstab
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
  ! Subroutine to implement BiConjugate Gradient Stabilised iteration
  !
  ! $Id: huti_bicgstab.src,v 1.1.1.1 2005/04/15 10:31:18 vierinen Exp $



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

# 35 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_bicgstab.F90" 2

  !
  !*************************************************************************
  ! Definitions to make the code more understandable and to make it look
  ! like the pseudo code
  !




# 61 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_bicgstab.F90"


contains


  !*************************************************************************
  !*************************************************************************
  ! Single precision version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_sbicgstabsolv  ( ndim, wrkdim, xvec, rhsvec, &
       ipar, dpar, work, matvecsubr, pcondlsubr, &
       pcondrsubr, dotprodfun, normfun, stopcfun )

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

    real :: rho, oldrho, alpha, beta, omega
    integer :: iter_count

    real :: residual, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual BiCGSTAB begins here (look the pseudo code in the
    ! "Templates..."-book, page 27)
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

    call matvecsubr( xvec, work(:,8), ipar )
    work(:,8) = rhsvec - work(:,8)
    work(:,1) = work(:,8)
    work(:,2) = 0; work(:,4) = 0
    oldrho = 1; omega = 1; alpha = 0

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    rho = dotprodfun( ipar(3), work(:,1), 1, work(:,8), 1 )
    if ( rho .eq. 0 ) then
       ipar(30) = 35
       go to 1000
    end if

    beta = ( rho * alpha ) / ( oldrho * omega )
    work(:,2) = work(:,8) + beta * ( work(:,2) - omega * work(:,4) )

    call pcondlsubr( work(:,4), work(:,2), ipar )
    call pcondrsubr( work(:,3), work(:,4), ipar )
    call matvecsubr( work(:,3), work(:,4), ipar )

    alpha = rho / dotprodfun( ipar(3), work(:,1), 1, work(:,4), 1 )
    work(:,5) = work(:,8) - alpha * work(:,4)

    residual = normfun( ipar(3), work(:,5), 1 )
    if ( residual .lt. 1.17549435E-38 ) then
       xvec = xvec + alpha * work(:,3)
       !ipar(30) = 36
       ipar(30) = 1
       go to 1000
    end if

    call pcondlsubr( work(:,7), work(:,5), ipar )
    call pcondrsubr( work(:,6), work(:,7), ipar )
    call matvecsubr( work(:,6), work(:,7), ipar )

    omega = ( dotprodfun( ipar(3), work(:,7), 1, work(:,5), 1 ) ) / &
         ( dotprodfun( ipar(3), work(:,7), 1, work(:,7), 1 ) )
    xvec = xvec + alpha * work(:,3) + omega * work(:,6)
    work(:,8) = work(:,5) - omega * work(:,7)

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 )
    case (1)
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 ) / rhsnorm
    case (2)
       residual = normfun( ipar(3), work(:,8), 1 )
    case (3)
       residual = normfun( ipar(3), work(:,8), 1 ) / rhsnorm
    case (4)
       residual = normfun( ipar(3), work(:,8), 1 ) / precrhsnorm
    case (5)
       work(:,3) = alpha * work(:,3) + omega * work(:,6)
       residual = normfun( ipar(3), work(:,3), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,8), ipar, dpar )
    case default
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 )
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
    
    if ( omega .eq. 0 ) then
       ipar(30) = 37
       go to 1000
    end if

    oldrho = rho

    !
    ! Return back to the iteration loop (without initialization)
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

  end subroutine  huti_sbicgstabsolv

  !*************************************************************************



  !*************************************************************************
  !*************************************************************************
  ! Double precision version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_dbicgstabsolv  ( ndim, wrkdim, xvec, rhsvec, &
       ipar, dpar, work, matvecsubr, pcondlsubr, &
       pcondrsubr, dotprodfun, normfun, stopcfun )

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

    double precision :: rho, oldrho, alpha, beta, omega
    integer :: iter_count, i

    double precision :: residual, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual BiCGSTAB begins here (look the pseudo code in the
    ! "Templates..."-book, page 27)
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

    call matvecsubr( xvec, work(:,8), ipar )
# 369 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_bicgstab.F90"
    work(:,8) = rhsvec - work(:,8)
    work(:,1) = work(:,8)
    work(:,2) = 0; work(:,4) = 0

    oldrho = 1; omega = 1; alpha = 0

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    rho = dotprodfun( ipar(3), work(:,1), 1, work(:,8), 1 )
    if ( rho .eq. 0 ) then
       ipar(30) = 35
       go to 1000
    end if

    beta = ( rho * alpha ) / ( oldrho * omega )








    work(:,2) = work(:,8) + beta * ( work(:,2) - omega * work(:,4) )


    call pcondlsubr( work(:,4), work(:,2), ipar )
    call pcondrsubr( work(:,3), work(:,4), ipar )
    call matvecsubr( work(:,3), work(:,4), ipar )

    alpha = rho / dotprodfun( ipar(3), work(:,1), 1, work(:,4), 1 )







    work(:,5) = work(:,8) - alpha * work(:,4)


    residual = normfun( ipar(3), work(:,5), 1 )
    if ( residual .lt. 1.17549435E-38 ) then







       xvec = xvec + alpha * work(:,3)

       ipar(30) = 1
       !ipar(30) = 36
       go to 1000
    end if

    call pcondlsubr( work(:,7), work(:,5), ipar )
    call pcondrsubr( work(:,6), work(:,7), ipar )
    call matvecsubr( work(:,6), work(:,7), ipar )

    omega = ( dotprodfun( ipar(3), work(:,7), 1, work(:,5), 1 ) ) / &
         ( dotprodfun( ipar(3), work(:,7), 1, work(:,7), 1 ) )

# 446 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_bicgstab.F90"
    xvec = xvec + alpha * work(:,3) + omega * work(:,6)
    work(:,8) = work(:,5) - omega * work(:,7)


    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call matvecsubr( xvec, work(:,6), ipar )







       work(:,3) = work(:,6) - rhsvec

       residual = normfun( ipar(3), work(:,3), 1 )
    case (1)
       call matvecsubr( xvec, work(:,6), ipar )







       work(:,3) = work(:,6) - rhsvec

       residual = normfun( ipar(3), work(:,3), 1 ) / rhsnorm
    case (2)
       residual = normfun( ipar(3), work(:,8), 1 )
    case (3)
       residual = normfun( ipar(3), work(:,8), 1 ) / rhsnorm
    case (4)
       residual = normfun( ipar(3), work(:,8), 1 ) / precrhsnorm
    case (5)







       work(:,3) = alpha * work(:,3) + omega * work(:,6)

       residual = normfun( ipar(3), work(:,3), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,8), ipar, dpar )
    case default
       call matvecsubr( xvec, work(:,6), ipar )







       work(:,3) = work(:,6) - rhsvec

       residual = normfun( ipar(3), work(:,3), 1 )
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

    if ( omega .eq. 0 ) then
       ipar(30) = 37
       go to 1000
    end if

    IF( residual /= residual .OR. residual > dpar(2) ) THEN
      ipar(30) = 3
      GOTO 1000
    END IF
    
    oldrho = rho

    !
    ! Return back to the iteration loop (without initialization)
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

  end subroutine  huti_dbicgstabsolv

  !*************************************************************************


  !*************************************************************************
  !*************************************************************************
  ! Complex version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_cbicgstabsolv  ( ndim, wrkdim, xvec, rhsvec, &
       ipar, dpar, work, matvecsubr, pcondlsubr, &
       pcondrsubr, dotprodfun, normfun, stopcfun )

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

    complex :: rho, oldrho, alpha, beta, omega
    integer :: iter_count

    real :: residual, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual BiCGSTAB begins here (look the pseudo code in the
    ! "Templates..."-book, page 27)
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

    call matvecsubr( xvec, work(:,8), ipar )
    work(:,8) = rhsvec - work(:,8)
    work(:,1) = work(:,8)
    work(:,2) = 0; work(:,4) = 0
    oldrho = 1; omega = 1; alpha = 0

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    rho = dotprodfun( ipar(3), work(:,1), 1, work(:,8), 1 )
    if ( rho .eq. 0 ) then
       ipar(30) = 35
       go to 1000
    end if

    beta = ( rho * alpha ) / ( oldrho * omega )
    work(:,2) = work(:,8) + beta * ( work(:,2) - omega * work(:,4) )

    call pcondlsubr( work(:,4), work(:,2), ipar )
    call pcondrsubr( work(:,3), work(:,4), ipar )
    call matvecsubr( work(:,3), work(:,4), ipar )

    alpha = rho / dotprodfun( ipar(3), work(:,1), 1, work(:,4), 1 )
    work(:,5) = work(:,8) - alpha * work(:,4)

    residual = normfun( ipar(3), work(:,5), 1 )
    if ( residual .lt. 1.17549435E-38 ) then
       xvec = xvec + alpha * work(:,3)
       ipar(30) = 1
       !ipar(30) = 36
       go to 1000
    end if

    call pcondlsubr( work(:,7), work(:,5), ipar )
    call pcondrsubr( work(:,6), work(:,7), ipar )
    call matvecsubr( work(:,6), work(:,7), ipar )

    omega = ( dotprodfun( ipar(3), work(:,7), 1, work(:,5), 1 ) ) / &
         ( dotprodfun( ipar(3), work(:,7), 1, work(:,7), 1 ) )
    xvec = xvec + alpha * work(:,3) + omega * work(:,6)
    work(:,8) = work(:,5) - omega * work(:,7)

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 )
    case (1)
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 ) / rhsnorm
    case (2)
       residual = normfun( ipar(3), work(:,8), 1 )
    case (3)
       residual = normfun( ipar(3), work(:,8), 1 ) / rhsnorm
    case (4)
       residual = normfun( ipar(3), work(:,8), 1 ) / precrhsnorm
    case (5)
       work(:,3) = alpha * work(:,3) + omega * work(:,6)
       residual = normfun( ipar(3), work(:,3), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,8), ipar, dpar )
    case default
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 )
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
    
    if ( omega .eq. 0 ) then
       ipar(30) = 37
       go to 1000
    end if

    oldrho = rho

    !
    ! Return back to the iteration loop (without initialization)
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

  end subroutine  huti_cbicgstabsolv

  !*************************************************************************


  !*************************************************************************
  !*************************************************************************
  ! Double complex version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_zbicgstabsolv  ( ndim, wrkdim, xvec, rhsvec, &
       ipar, dpar, work, matvecsubr, pcondlsubr, &
       pcondrsubr, dotprodfun, normfun, stopcfun )

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

    double complex :: rho, oldrho, alpha, beta, omega
    integer :: iter_count

    double precision :: residual, rhsnorm, precrhsnorm

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual BiCGSTAB begins here (look the pseudo code in the
    ! "Templates..."-book, page 27)
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

    call matvecsubr( xvec, work(:,8), ipar )
    work(:,8) = rhsvec - work(:,8)
    work(:,1) = work(:,8)
    work(:,2) = 0; work(:,4) = 0
    oldrho = 1; omega = 1; alpha = 0

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    rho = dotprodfun( ipar(3), work(:,1), 1, work(:,8), 1 )
    if ( rho .eq. 0 ) then
       ipar(30) = 35
       go to 1000
    end if

    beta = ( rho * alpha ) / ( oldrho * omega )
    work(:,2) = work(:,8) + beta * ( work(:,2) - omega * work(:,4) )

    call pcondlsubr( work(:,4), work(:,2), ipar )
    call pcondrsubr( work(:,3), work(:,4), ipar )
    call matvecsubr( work(:,3), work(:,4), ipar )

    alpha = rho / dotprodfun( ipar(3), work(:,1), 1, work(:,4), 1 )
    work(:,5) = work(:,8) - alpha * work(:,4)

    residual = normfun( ipar(3), work(:,5), 1 )
    if ( residual .lt. 1.17549435E-38 ) then
       xvec = xvec + alpha * work(:,3)
       !ipar(30) = 36
       ipar(30) = 1
       go to 1000
    end if

    call pcondlsubr( work(:,7), work(:,5), ipar )
    call pcondrsubr( work(:,6), work(:,7), ipar )
    call matvecsubr( work(:,6), work(:,7), ipar )

    omega = ( dotprodfun( ipar(3), work(:,7), 1, work(:,5), 1 ) ) / &
         ( dotprodfun( ipar(3), work(:,7), 1, work(:,7), 1 ) )
    xvec = xvec + alpha * work(:,3) + omega * work(:,6)
    work(:,8) = work(:,5) - omega * work(:,7)

    !
    ! Check the convergence against selected stopping criterion
    !

    select case (ipar(12))
    case (0)
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 )
    case (1)
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 ) / rhsnorm
    case (2)
       residual = normfun( ipar(3), work(:,8), 1 )
    case (3)
       residual = normfun( ipar(3), work(:,8), 1 ) / rhsnorm
    case (4)
       residual = normfun( ipar(3), work(:,8), 1 ) / precrhsnorm
    case (5)
       work(:,3) = alpha * work(:,3) + omega * work(:,6)
       residual = normfun( ipar(3), work(:,3), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,8), ipar, dpar )
    case default
       call matvecsubr( xvec, work(:,6), ipar )
       work(:,3) = work(:,6) - rhsvec
       residual = normfun( ipar(3), work(:,3), 1 )
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
    
    if ( omega .eq. 0 ) then
       ipar(30) = 37
       go to 1000
    end if

    oldrho = rho

    !
    ! Return back to the iteration loop (without initialization)
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

  end subroutine  huti_zbicgstabsolv

  !*************************************************************************


end module huti_bicgstab
