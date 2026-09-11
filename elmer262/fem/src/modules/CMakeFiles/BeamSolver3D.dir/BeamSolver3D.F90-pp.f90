# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BeamSolver3D.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BeamSolver3D.F90"
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
# 59 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BeamSolver3D.F90"

!------------------------------------------------------------------------------
SUBROUTINE TimoshenkoSolver_Init0(Model, Solver, dt, Transient)
!------------------------------------------------------------------------------
  USE DefUtils
  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Model_t) :: Model
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp) :: dt
  LOGICAL :: Transient
!------------------------------------------------------------------------------
  TYPE(ValueList_t), POINTER :: SolverPars, Simulation
  LOGICAL :: Found, MeshDisplacementActive
!------------------------------------------------------------------------------
  SolverPars => GetSolverParams()

  CALL ListAddInteger(SolverPars, 'Variable DOFs', 6)
  CALL ListAddNewString(SolverPars, 'Variable', 'Deflection[U:3 Theta:3]')
  CALL ListAddNewString(SolverPars, 'Element', 'p:1 b:1')

  CALL ListAddNewLogical(SolverPars, 'Bubbles in Global System', .FALSE.)
  CALL ListAddNewLogical(SolverPars, 'Use Global Mass Matrix',.TRUE.)
  IF (Transient) THEN
    CALL ListAddInteger(SolverPars, 'Time derivative order', 2)
    CALL ListAddNewString(SolverPars, 'Timestepping Method', 'Bossak')
  END IF

  MeshDisplacementActive = GetLogical(SolverPars, 'Displace Mesh', Found)
  IF (MeshDisplacementActive) THEN
    Simulation => GetSimulation()
    CALL ListAddLogical(Simulation, 'Initialize Dirichlet Conditions', .FALSE.) 
  END IF
  
  CALL ListAddNewLogical(SolverPars,'Beam Solver',.TRUE.)
!------------------------------------------------------------------------------
END SUBROUTINE TimoshenkoSolver_Init0
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
SUBROUTINE TimoshenkoSolver(Model, Solver, dt, TransientSimulation)
!------------------------------------------------------------------------------
  USE DefUtils
  USE SolidMechanicsUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Model_t) :: Model
  TYPE(Solver_t) :: Solver
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  TYPE(Element_t), POINTER :: Element
  TYPE(Mesh_t), POINTER :: Mesh
  LOGICAL :: Found
  INTEGER :: K, Active, n, nb, nd
  INTEGER :: iter, maxiter
  REAL(KIND=dp) :: Norm
  LOGICAL :: HarmonicAssembly, MassAssembly, MeshDisplacementActive
  TYPE(ValueList_t), POINTER :: Params
!------------------------------------------------------------------------------

  CALL DefaultStart()

  IF (.NOT. ListCheckPresentAnyMaterial(Model, 'Principal Direction 2') .AND. &
      .NOT. ListCheckPresentAnyMaterial(Model, 'Director')) THEN
    CALL Warn('TimoshenkoSolver', &
        'Principal axes unspecified, assuming a circular cross section')
  END IF
  
  Params => GetSolverParams()
  
  maxiter = ListGetInteger(Params, &
      'Nonlinear System Max Iterations', Found, minv=1)
  IF (.NOT. Found ) maxiter = 1

  HarmonicAssembly = EigenOrHarmonicAnalysis() &
      .OR. ListGetLogical( Params,'Harmonic Mode',Found ) 
  MassAssembly = TransientSimulation .OR. HarmonicAssembly

  MeshDisplacementActive = GetLogical(Params, 'Displace Mesh', Found)
  IF (MeshDisplacementActive) THEN
    Mesh => GetMesh()
    CALL Info('TimoshenkoSolver', 'Returning the mesh to its reference position', Level=4)     
    CALL DisplaceMesh(Mesh, Solver % Variable % Values, -1, Solver % Variable % Perm, &
        6, .FALSE., 3)      
  END IF

  !--------------------------
  ! Nonlinear iteration loop:
  !--------------------------
  DO iter=1,maxiter
    !-----------------
    ! System assembly:
    !-----------------
    CALL DefaultInitialize()
    Active = GetNOFActive()
    DO K=1,Active
      Element => GetActiveElement(K)

      IF ( .NOT. (GetElementFamily(Element) == 2) ) CYCLE

      n  = GetElementNOFNodes()
      nd = GetElementNOFDOFs()
      nb = GetElementNOFBDOFs()

      CALL BeamStiffnessMatrix(Element, n, nd+nb, nb, TransientSimulation, &
          MassAssembly=MassAssembly, HarmonicAssembly=HarmonicAssembly)      
    END DO

    CALL DefaultFinishBulkAssembly()

    CALL DefaultFinishBoundaryAssembly()
    CALL DefaultFinishAssembly()
    CALL DefaultDirichletBCs()

    !-----------------------
    ! Call a linear solver:
    !-----------------------
    Norm = DefaultSolve()
    IF ( DefaultConverged() ) EXIT    

  END DO

  CALL DefaultFinish()

  IF (MeshDisplacementActive) THEN
    CALL Info('TimoshenkoSolver', 'Displacing the mesh with computed displacement field', Level=4)
    CALL DisplaceMesh(Mesh, Solver % Variable % Values, 1, Solver % Variable % Perm, &
        6, .FALSE., 3)
  END IF
!------------------------------------------------------------------------------
END SUBROUTINE TimoshenkoSolver
!------------------------------------------------------------------------------
