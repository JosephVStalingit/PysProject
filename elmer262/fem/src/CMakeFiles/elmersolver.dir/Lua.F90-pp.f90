# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/Lua.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/Lua.F90"
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
# 36 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/Lua.F90"


# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build/fem/config.h" 1
# 38 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/Lua.F90" 2



!-------------------------------------------------------------------------------
module Lua ! {{{
!-------------------------------------------------------------------------------
use ISO_C_BINDING
implicit none
private

!-Type declarations-------------------------------------------------------------
type, public :: LuaState_t
  private
  REAL(KIND=c_double), POINTER, PUBLIC :: tx(:) => NULL() ! This table will hold values for tx array
  type(c_ptr) :: L = c_null_ptr
  logical, public :: initialized=.false.
end type
!-------------------------------------------------------------------------------

type(LuaState_t), PUBLIC :: LuaState
!$OMP THREADPRIVATE(LuaState)

# 420 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/Lua.F90"

!-------------------------------------------------------------------------------
end module ! Lua }}}
!-------------------------------------------------------------------------------
