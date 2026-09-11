# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/SlaveSolverSlots/CountSolver.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/SlaveSolverSlots/CountSolver.F90"
!-----------------------------------------------------------------------------
!> Solver counts how many times it is visited and returns that as the norm.
!------------------------------------------------------------------------------
SUBROUTINE CountSolver( Model,Solver,dt,TransientSimulation )
!------------------------------------------------------------------------------
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  INTEGER, SAVE :: VisitedTimes = 0

  VisitedTimes = VisitedTimes + 1
  CALL Info('CountSolver','Solver visited times: '//I2S(VisitedTimes))

  Solver % variable % values = 1.0_dp * VisitedTimes
  Solver % variable % norm = 1.0_dp * VisitedTimes
  
!------------------------------------------------------------------------------
END SUBROUTINE CountSolver
!------------------------------------------------------------------------------
