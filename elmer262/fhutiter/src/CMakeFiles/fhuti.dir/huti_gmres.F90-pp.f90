# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_gmres.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_gmres.F90"
module huti_gmres
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
  ! Subroutines to implement Generalized Minimum Residual iterative method
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

# 32 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_gmres.F90" 2

  !*************************************************************************
  !*************************************************************************
  !
  ! These subroutines are based on a book by Barret et al.:
  ! "Templates for the Solution of Linear Systems: Building Blocks for
  !  Iterative Methods", 1993.
  !
  ! All matrix-vector operations are done externally, so we do not need
  ! to know about the matrix structure (sparse or dense). So has the
  ! memory allocation for the working arrays done also externally.

  !*************************************************************************
  ! Work array is used in the following order:
  ! work(:,1) = z
  ! work(:,2) = p
  ! work(:,3) = q
  ! work(:,4) = r
  !
  ! Definitions to make the code more understandable and to make it look
  ! like the pseudo code (these are common to all precisions)
  !




# 70 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_gmres.F90"

contains

  !*************************************************************************

  !*************************************************************************
  !*************************************************************************
  ! Single precision version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_sgmressolv  ( ndim, wrkdim, xvec, rhsvec, &
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

    integer :: iter_count
    real :: residual, rhsnorm, precrhsnorm
    real :: bnrm, alpha, beta

    INTEGER :: reit, info, i, j, k, l, m, n

    real :: temp, temp2, error, gamma

    ! Local arrays

    real, DIMENSION(ipar(15)+1,ipar(15)+1) :: H
    real, &
         DIMENSION((ipar(15)+1)*(ipar(15)+1)) :: HLU
    real, DIMENSION(ipar(15)+1) :: CS, SN, Y

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual GMRES begins here (look the pseudo code in the
    ! "Templates..."-book, page 20)
    !
    ! First the initialization part
    !

    iter_count = 1

    bnrm = normfun( ipar(3), rhsvec, 1 )

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 ) then
       rhsnorm = bnrm
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,5), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,5), 1 )
    end if

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_srandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call pcondrsubr( work(:,5), xvec, ipar )
    call matvecsubr( work(:,5), work(:,2), ipar )
    work(:,5) = rhsvec - work(:,2)
    call pcondlsubr( work(:,2), work(:,5), ipar )

    m = ipar(15)
    work(:,6+1-1:6+m+1-1) = 0
    H = 0
    CS = 0
    SN = 0
    work(:,4) = 0
    work(1,4) = 1.0

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    call pcondrsubr( work(:,5), xvec, ipar )
    call matvecsubr( work(:,5), work(:,2), ipar )
    work(:,5) = rhsvec - work(:,2)
    call pcondlsubr( work(:,2), work(:,5), ipar )

    alpha = normfun( ipar(3), work(:,2), 1 )
    if ( alpha .eq. 0 ) then
       ipar(30) = 40
       go to 1000
    end if

    work(:,6+1-1) = work(:,2) / alpha
    work(:,3) = alpha * work(:,4)

    !
    ! Construct orthonormal
    !

    DO i = 1, m
       call pcondrsubr( work(:,1), work(:,6+i-1), ipar )
       call matvecsubr( work(:,1), work(:,5), ipar )
       call pcondlsubr( work(:,1), work(:,5), ipar )

       DO k = 1, i
          H(k,i) = dotprodfun( ipar(3), work(:,1), 1, work(:,6+k-1), 1 )
          work(:,1) = work(:,1) - H(k,i) * work(:,6+k-1)
       END DO

       beta = normfun( ipar(3), work(:,1), 1 )
       if ( beta .eq. 0 ) then
          ipar(30) = 41
          go to 1000
       end if

       H(i+1,i) = beta
       work(:,6+i+1-1) = work(:,1) / H(i+1, i)

       !
       ! Compute the Givens rotation
       !

       DO k = 1, i-1
          temp = CS(k) * H(k,i) + SN(k) * H(k+1,i)
          H(k+1,i) = -1 * SN(k) * H(k,i) + CS(k) * H(k+1,i)
          H(k,i) = temp
       END DO

       IF ( H(i+1,i) .eq. 0 ) THEN
          CS(i) = 1; SN(i) = 0
       ELSE
          IF ( abs( H(i+1,i) ) .gt. abs( H(i,i) ) ) THEN
             temp2 = H(i,i) / H(i+1,i)
             SN(i) = 1 / sqrt( 1 + ( temp2 * temp2 ))
             CS(i) = temp2 * SN(i)
          ELSE
             temp2 = H(i+1,i) / H(i,i)
             CS(i) = 1 / sqrt( 1 + ( temp2 * temp2 ))
             SN(i) = temp2 * CS(i)
          END IF
       END IF

       temp = CS(i) * work(i,3)
       work(i+1,3) = -1 * SN(i) * work(i,3)
       work(i,3) = temp

       H(i,i) = ( CS(i) * H(i,i) ) + ( SN(i) * H(i+1,i) )
       H(i+1,i) = 0

       error = abs( work(i+1,3) ) / bnrm 
       IF ( REAL( error ) .lt.  dpar(1) ) THEN

          HLU = 0; j = 1
          do k = 1, i
             do l = 1, i
                HLU(j) = H(l,k)
                j = j + 1
             end do
          end do

          call  huti_slusolve  ( i, HLU, Y, work(:,3) )

          xvec = xvec + MATMUL( work(:,6+1-1:6+i-1), Y(1:i) )

          EXIT
       END IF

    END DO

    IF ( REAL( error ) .lt. dpar(1) ) THEN
       GOTO 500
    END IF

    HLU = 0; j = 1
    do k = 1, m
       do l = 1, m
          HLU(j) = H(l,k)
          j = j + 1
       end do
    end do

    call  huti_slusolve  ( m, HLU, Y, work(:,3) )

    xvec = xvec + MATMUL( work(:,6+1-1:6+m-1), Y(1:m) )

500 CONTINUE

    !
    ! Check the convergence
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = rhsvec - work(:,2)
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 )
    case (1)
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = rhsvec - work(:,2)
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 )
    case (3)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 ) / precrhsnorm
    case (5)
       work(:,5) = MATMUL( work(:,6+1-1:6+m-1), Y(1:m) )
       residual = normfun( ipar(3), work(:,5), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,2), ipar, dpar )
    case default
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = work(:,2) - rhsvec
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 )
    end select

    work(m+1,3) = normfun( ipar(3), work(:,2), 1 )

    !
    ! Print debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          WRITE (*, '(A, I8, E11.4)') '   gmres:',iter_count, residual
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
       WRITE (*, '(A, I8, E11.4)') '   gmres:',iter_count, residual
    end if

    ipar(31) = iter_count
    call pcondrsubr( work(:,5), xvec, ipar )
    xvec = work(:,5)
    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_sgmressolv

  !*************************************************************************

  !*************************************************************************
  !*************************************************************************
  ! Double precision version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_dgmressolv  ( ndim, wrkdim, xvec, rhsvec, &
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

    integer :: iter_count
    double precision :: residual, rhsnorm, precrhsnorm
    double precision :: bnrm, alpha, beta

    INTEGER :: reit, info, i, j, k, l, m, n, ii, jj

    double precision :: temp, temp2, error, gamma

    ! Local arrays

    double precision, DIMENSION(ipar(15)+1,ipar(15)+1) :: H
    double precision, &
         DIMENSION((ipar(15)+1)*(ipar(15)+1)) :: HLU
    double precision, DIMENSION(ipar(15)+1) :: CS, SN, Y

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual GMRES begins here (look the pseudo code in the
    ! "Templates..."-book, page 20)
    !
    ! First the initialization part
    !

    iter_count = 1

    bnrm = normfun( ipar(3), rhsvec, 1 )

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 ) then
       rhsnorm = bnrm
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,5), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,5), 1 )
    end if

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_drandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then







        xvec = 1

    end if

    call pcondrsubr( work(:,5), xvec, ipar )
    call matvecsubr( work(:,5), work(:,2), ipar )







    work(:,5) = rhsvec - work(:,2)

    call pcondlsubr( work(:,2), work(:,5), ipar )

    m = ipar(15)
# 505 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_gmres.F90"
    work(:,6+1-1:6+m+1-1) = 0
    work(:,4) = 0

    H = 0
    CS = 0
    SN = 0
    work(1,4) = 1.0

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    call pcondrsubr( work(:,5), xvec, ipar )
    call matvecsubr( work(:,5), work(:,2), ipar )







    work(:,5) = rhsvec - work(:,2)

    call pcondlsubr( work(:,2), work(:,5), ipar )

    alpha = normfun( ipar(3), work(:,2), 1 )
    if ( alpha .eq. 0 ) then
       ipar(30) = 40
       go to 1000
    end if

# 553 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fhutiter/src/huti_gmres.F90"
    work(:,6+1-1) = work(:,2) / alpha
    work(:,3) = alpha * work(:,4)


    !
    ! Construct orthonormal
    !

    DO i = 1, m
       call pcondrsubr( work(:,1), work(:,6+i-1), ipar )
       call matvecsubr( work(:,1), work(:,5), ipar )
       call pcondlsubr( work(:,1), work(:,5), ipar )

       DO k = 1, i
          H(k,i) = dotprodfun( ipar(3), work(:,1), 1, work(:,6+k-1), 1 )







          work(:,1) = work(:,1) - H(k,i) * work(:,6+k-1)

       END DO

       beta = normfun( ipar(3), work(:,1), 1 )
       if ( beta .eq. 0 ) then
          ipar(30) = 41
          go to 1000
       end if

       H(i+1,i) = beta







       work(:,6+i+1-1) = work(:,1) / H(i+1, i)

       
       !
       ! Compute the Givens rotation
       !

       DO k = 1, i-1
          temp = CS(k) * H(k,i) + SN(k) * H(k+1,i)
          H(k+1,i) = -1 * SN(k) * H(k,i) + CS(k) * H(k+1,i)
          H(k,i) = temp
       END DO

       IF ( H(i+1,i) .eq. 0 ) THEN
          CS(i) = 1; SN(i) = 0
       ELSE
          IF ( abs( H(i+1,i) ) .gt. abs( H(i,i) ) ) THEN
             temp2 = H(i,i) / H(i+1,i)
             SN(i) = 1 / sqrt( 1 + ( temp2 * temp2 ))
             CS(i) = temp2 * SN(i)
          ELSE
             temp2 = H(i+1,i) / H(i,i)
             CS(i) = 1 / sqrt( 1 + ( temp2 * temp2 ))
             SN(i) = temp2 * CS(i)
          END IF
       END IF

       temp = CS(i) * work(i,3)
       work(i+1,3) = -1 * SN(i) * work(i,3)
       work(i,3) = temp

       H(i,i) = ( CS(i) * H(i,i) ) + ( SN(i) * H(i+1,i) )
       H(i+1,i) = 0

       error = abs( work(i+1,3) ) / bnrm 
       IF ( REAL( error ) .lt.  dpar(1) ) THEN

          HLU = 0; j = 1
          do k = 1, i
             do l = 1, i
                HLU(j) = H(l,k)
                j = j + 1
             end do
          end do

          call  huti_dlusolve  ( i, HLU, Y, work(:,3) )




          xvec = xvec + MATMUL( work(:,6+1-1:6+i-1), Y(1:i) )

          
          EXIT
       END IF

    END DO

    IF ( REAL( error ) .lt. dpar(1) ) THEN
       GOTO 500
    END IF

    HLU = 0; j = 1
    do k = 1, m
       do l = 1, m
          HLU(j) = H(l,k)
          j = j + 1
       end do
    end do

    call  huti_dlusolve  ( m, HLU, Y, work(:,3) )




    xvec = xvec + MATMUL( work(:,6+1-1:6+m-1), Y(1:m) )



500 CONTINUE

    !
    ! Check the convergence
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )







       work(:,5) = rhsvec - work(:,2)

       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 )
    case (1)
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )







       work(:,5) = rhsvec - work(:,2)

       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,2), ipar )







       work(:,2) = work(:,2) - rhsvec

       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 )
    case (3)
       call matvecsubr( xvec, work(:,2), ipar )







       work(:,2) = work(:,2) - rhsvec

       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,2), ipar )







       work(:,2) = work(:,2) - rhsvec

       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 ) / precrhsnorm
    case (5)



       work(:,5) = MATMUL( work(:,6+1-1:6+m-1), Y(1:m) )

       residual = normfun( ipar(3), work(:,5), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,2), ipar, dpar )
    case default
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )







       work(:,5) = work(:,2) - rhsvec

       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 )
    end select

    work(m+1,3) = normfun( ipar(3), work(:,2), 1 )

    !
    ! Print debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          WRITE (*, '(A, I8, E11.4)') '   gmres:',iter_count, residual
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
       WRITE (*, '(A, I8, E11.4)') '   gmres:',iter_count, residual
    end if

    ipar(31) = iter_count
    call pcondrsubr( work(:,5), xvec, ipar )
    xvec = work(:,5)
    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_dgmressolv

  !*************************************************************************


  !*************************************************************************
  !*************************************************************************
  ! Complex version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_cgmressolv  ( ndim, wrkdim, xvec, rhsvec, &
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

    integer :: iter_count
    real :: residual, rhsnorm, precrhsnorm
    real :: bnrm, alpha, beta

    INTEGER :: reit, info, i, j, k, l, m, n

    complex :: temp, temp2, error, gamma

    ! Local arrays

    complex, DIMENSION(ipar(15)+1,ipar(15)+1) :: H
    complex, &
         DIMENSION((ipar(15)+1)*(ipar(15)+1)) :: HLU
    complex, DIMENSION(ipar(15)+1) :: CS, SN, Y

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual GMRES begins here (look the pseudo code in the
    ! "Templates..."-book, page 20)
    !
    ! First the initialization part
    !

    iter_count = 1

    bnrm = normfun( ipar(3), rhsvec, 1 )

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 ) then
       rhsnorm = bnrm
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,5), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,5), 1 )
    end if

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_crandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call pcondrsubr( work(:,5), xvec, ipar )
    call matvecsubr( work(:,5), work(:,2), ipar )
    work(:,5) = rhsvec - work(:,2)
    call pcondlsubr( work(:,2), work(:,5), ipar )

    m = ipar(15)
    work(:,6+1-1:6+m+1-1) = 0
    H = 0
    CS = 0
    SN = 0
    work(:,4) = 0
    work(1,4) = 1.0

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    call pcondrsubr( work(:,5), xvec, ipar )
    call matvecsubr( work(:,5), work(:,2), ipar )
    work(:,5) = rhsvec - work(:,2)
    call pcondlsubr( work(:,2), work(:,5), ipar )

    alpha = normfun( ipar(3), work(:,2), 1 )
    if ( alpha .eq. 0 ) then
       ipar(30) = 40
       go to 1000
    end if

    work(:,6+1-1) = work(:,2) / alpha
    work(:,3) = alpha * work(:,4)

    !
    ! Construct orthonormal
    !

    DO i = 1, m
       call pcondrsubr( work(:,1), work(:,6+i-1), ipar )
       call matvecsubr( work(:,1), work(:,5), ipar )
       call pcondlsubr( work(:,1), work(:,5), ipar )

       DO k = 1, i
          H(k,i) = dotprodfun( ipar(3), work(:,1), 1, work(:,6+k-1), 1 )
          work(:,1) = work(:,1) - H(k,i) * work(:,6+k-1)
       END DO

       beta = normfun( ipar(3), work(:,1), 1 )
       if ( beta .eq. 0 ) then
          ipar(30) = 41
          go to 1000
       end if

       H(i+1,i) = beta
       work(:,6+i+1-1) = work(:,1) / H(i+1, i)

       !
       ! Compute the Givens rotation
       !

       DO k = 1, i-1
          temp = CS(k) * H(k,i) + SN(k) * H(k+1,i)
          H(k+1,i) = -1 * SN(k) * H(k,i) + CS(k) * H(k+1,i)
          H(k,i) = temp
       END DO

       IF ( H(i+1,i) .eq. 0 ) THEN
          CS(i) = 1; SN(i) = 0
       ELSE
          IF ( abs( H(i+1,i) ) .gt. abs( H(i,i) ) ) THEN
             temp2 = H(i,i) / H(i+1,i)
             SN(i) = 1 / sqrt( 1 + ( temp2 * temp2 ))
             CS(i) = temp2 * SN(i)
          ELSE
             temp2 = H(i+1,i) / H(i,i)
             CS(i) = 1 / sqrt( 1 + ( temp2 * temp2 ))
             SN(i) = temp2 * CS(i)
          END IF
       END IF

       temp = CS(i) * work(i,3)
       work(i+1,3) = -1 * SN(i) * work(i,3)
       work(i,3) = temp

       H(i,i) = ( CS(i) * H(i,i) ) + ( SN(i) * H(i+1,i) )
       H(i+1,i) = 0

       error = abs( work(i+1,3) ) / bnrm 
       IF ( REAL( error ) .lt.  dpar(1) ) THEN

          HLU = 0; j = 1
          do k = 1, i
             do l = 1, i
                HLU(j) = H(l,k)
                j = j + 1
             end do
          end do

          call  huti_clusolve  ( i, HLU, Y, work(:,3) )

          xvec = xvec + MATMUL( work(:,6+1-1:6+i-1), Y(1:i) )

          EXIT
       END IF

    END DO

    IF ( REAL( error ) .lt. dpar(1) ) THEN
       GOTO 500
    END IF

    HLU = 0; j = 1
    do k = 1, m
       do l = 1, m
          HLU(j) = H(l,k)
          j = j + 1
       end do
    end do

    call  huti_clusolve  ( m, HLU, Y, work(:,3) )

    xvec = xvec + MATMUL( work(:,6+1-1:6+m-1), Y(1:m) )

500 CONTINUE

    !
    ! Check the convergence
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = rhsvec - work(:,2)
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 )
    case (1)
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = rhsvec - work(:,2)
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 )
    case (3)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 ) / precrhsnorm
    case (5)
       work(:,5) = MATMUL( work(:,6+1-1:6+m-1), Y(1:m) )
       residual = normfun( ipar(3), work(:,5), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,2), ipar, dpar )
    case default
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = work(:,2) - rhsvec
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 )
    end select

    work(m+1,3) = normfun( ipar(3), work(:,2), 1 )

    !
    ! Print debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          WRITE (*, '(A, I8, E11.4)') '   gmresz:',iter_count, residual
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
       WRITE (*, '(A, I8, E11.4)') '   gmresz:', iter_count, residual
    end if

    ipar(31) = iter_count
    call pcondrsubr( work(:,5), xvec, ipar )
    xvec = work(:,5)
    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_cgmressolv

  !*************************************************************************


  !*************************************************************************
  !*************************************************************************
  ! Double complex version
  !*************************************************************************
  !*************************************************************************

  subroutine  huti_zgmressolv  ( ndim, wrkdim, xvec, rhsvec, &
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

    integer :: iter_count
    double precision :: residual, rhsnorm, precrhsnorm
    double precision :: bnrm, alpha, beta

    INTEGER :: reit, info, i, j, k, l, m, n

    double complex :: temp, temp2, error, gamma

    ! Local arrays

    double complex, DIMENSION(ipar(15)+1,ipar(15)+1) :: H
    double complex, &
         DIMENSION((ipar(15)+1)*(ipar(15)+1)) :: HLU
    double complex, DIMENSION(ipar(15)+1) :: CS, SN, Y

    !
    ! End of variable declarations
    !*********************************************************************

    !*********************************************************************
    ! The actual GMRES begins here (look the pseudo code in the
    ! "Templates..."-book, page 20)
    !
    ! First the initialization part
    !

    iter_count = 1

    bnrm = normfun( ipar(3), rhsvec, 1 )

    ! Norms of right-hand side vector are used in convergence tests

    if ( ipar(12) .eq. 1 .or. & 
         ipar(12) .eq. 3 ) then
       rhsnorm = bnrm
    end if
    if ( ipar(12) .eq. 4 ) then
       call pcondlsubr( work(:,5), rhsvec, ipar )
       precrhsnorm = normfun( ipar(3), work(:,5), 1 )
    end if

    ! The following applies for all matrix operations in this solver

    ipar(6) = 0

    ! Generate vector xvec if needed

    if ( ipar(14) .eq. 0 ) then
       call  huti_zrandvec   ( xvec, ipar )
    else if ( ipar(14) .ne. 1 ) then
       xvec = 1
    end if

    call pcondrsubr( work(:,5), xvec, ipar )
    call matvecsubr( work(:,5), work(:,2), ipar )
    work(:,5) = rhsvec - work(:,2)
    call pcondlsubr( work(:,2), work(:,5), ipar )

    m = ipar(15)
    work(:,6+1-1:6+m+1-1) = 0
    H = 0
    CS = 0
    SN = 0
    work(:,4) = 0
    work(1,4) = 1.0

    !
    ! This is where the loop starts (that is we continue from here after
    ! the first iteration)
    !

300 continue

    call pcondrsubr( work(:,5), xvec, ipar )
    call matvecsubr( work(:,5), work(:,2), ipar )
    work(:,5) = rhsvec - work(:,2)
    call pcondlsubr( work(:,2), work(:,5), ipar )

    alpha = normfun( ipar(3), work(:,2), 1 )
    if ( alpha .eq. 0 ) then
       ipar(30) = 40
       go to 1000
    end if

    work(:,6+1-1) = work(:,2) / alpha
    work(:,3) = alpha * work(:,4)

    !
    ! Construct orthonormal
    !

    DO i = 1, m
       call pcondrsubr( work(:,1), work(:,6+i-1), ipar )
       call matvecsubr( work(:,1), work(:,5), ipar )
       call pcondlsubr( work(:,1), work(:,5), ipar )

       DO k = 1, i
          H(k,i) = dotprodfun( ipar(3), work(:,1), 1, work(:,6+k-1), 1 )
          work(:,1) = work(:,1) - H(k,i) * work(:,6+k-1)
       END DO

       beta = normfun( ipar(3), work(:,1), 1 )
       if ( beta .eq. 0 ) then
          ipar(30) = 41
          go to 1000
       end if

       H(i+1,i) = beta
       work(:,6+i+1-1) = work(:,1) / H(i+1, i)

       !
       ! Compute the Givens rotation
       !

       DO k = 1, i-1
          temp = CS(k) * H(k,i) + SN(k) * H(k+1,i)
          H(k+1,i) = -1 * SN(k) * H(k,i) + CS(k) * H(k+1,i)
          H(k,i) = temp
       END DO

       IF ( H(i+1,i) .eq. 0 ) THEN
          CS(i) = 1; SN(i) = 0
       ELSE
          IF ( abs( H(i+1,i) ) .gt. abs( H(i,i) ) ) THEN
             temp2 = H(i,i) / H(i+1,i)
             SN(i) = 1 / sqrt( 1 + ( temp2 * temp2 ))
             CS(i) = temp2 * SN(i)
          ELSE
             temp2 = H(i+1,i) / H(i,i)
             CS(i) = 1 / sqrt( 1 + ( temp2 * temp2 ))
             SN(i) = temp2 * CS(i)
          END IF
       END IF

       temp = CS(i) * work(i,3)
       work(i+1,3) = -1 * SN(i) * work(i,3)
       work(i,3) = temp

       H(i,i) = ( CS(i) * H(i,i) ) + ( SN(i) * H(i+1,i) )
       H(i+1,i) = 0

       error = abs( work(i+1,3) ) / bnrm 
       IF ( REAL( error ) .lt.  dpar(1) ) THEN

          HLU = 0; j = 1
          do k = 1, i
             do l = 1, i
                HLU(j) = H(l,k)
                j = j + 1
             end do
          end do

          call  huti_zlusolve  ( i, HLU, Y, work(:,3) )

          xvec = xvec + MATMUL( work(:,6+1-1:6+i-1), Y(1:i) )

          EXIT
       END IF

    END DO

    IF ( REAL( error ) .lt. dpar(1) ) THEN
       GOTO 500
    END IF

    HLU = 0; j = 1
    do k = 1, m
       do l = 1, m
          HLU(j) = H(l,k)
          j = j + 1
       end do
    end do

    call  huti_zlusolve  ( m, HLU, Y, work(:,3) )

    xvec = xvec + MATMUL( work(:,6+1-1:6+m-1), Y(1:m) )

500 CONTINUE

    !
    ! Check the convergence
    !

    select case (ipar(12))
    case (0)
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = rhsvec - work(:,2)
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 )
    case (1)
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = rhsvec - work(:,2)
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 ) / rhsnorm
    case (2)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 )
    case (3)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 ) / rhsnorm
    case (4)
       call matvecsubr( xvec, work(:,2), ipar )
       work(:,2) = work(:,2) - rhsvec
       call pcondlsubr( work(:,5), work(:,2), ipar )
       residual = normfun( ipar(3), work(:,5), 1 ) / precrhsnorm
    case (5)
       work(:,5) = MATMUL( work(:,6+1-1:6+m-1), Y(1:m) )
       residual = normfun( ipar(3), work(:,5), 1 )
    case (10)
       residual = stopcfun( xvec, rhsvec, work(:,2), ipar, dpar )
    case default
       call pcondrsubr( work(:,5), xvec, ipar )
       call matvecsubr( work(:,5), work(:,2), ipar )
       work(:,5) = work(:,2) - rhsvec
       call pcondlsubr( work(:,2), work(:,5), ipar )
       residual = normfun( ipar(3), work(:,2), 1 )
    end select

    work(m+1,3) = normfun( ipar(3), work(:,2), 1 )

    !
    ! Print debugging output if desired
    !

    if ( ipar(5) .ne. 0 ) then
       if ( mod(iter_count, ipar(5)) .eq. 0 ) then
          WRITE (*, '(A, I8, E11.4)') '   gmresz:',iter_count, residual
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
       WRITE (*, '(A,I8, E11.4)') '   gmresz:',iter_count, residual
    end if

    ipar(31) = iter_count
    call pcondrsubr( work(:,5), xvec, ipar )
    xvec = work(:,5)
    return

    ! End of execution
    !*********************************************************************

  end subroutine  huti_zgmressolv

  !*************************************************************************


end module huti_gmres
