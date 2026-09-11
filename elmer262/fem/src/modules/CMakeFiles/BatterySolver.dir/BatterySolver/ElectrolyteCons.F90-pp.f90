# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BatterySolver/ElectrolyteCons.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BatterySolver/ElectrolyteCons.F90"
!------------------------------------------------------------------------------
! For copyrights see the BatteryUtils.F90 file in this directory!
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
SUBROUTINE ElectrolyteCons_init( Model,Solver,dt,Transient )
  !------------------------------------------------------------------------------
  USE DefUtils
  IMPLICIT NONE
  !------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: Transient
  !------------------------------------------------------------------------------
  CHARACTER(*), PARAMETER :: Caller = 'ElectrolyteCons_init'
  TYPE(ValueList_t), POINTER :: Params
  LOGICAL :: Found

  Params => GetSolverParams()

  CALL ListAddNewString( Params,'Variable','Ce')

  IF( ListGetLogical( Params,'Linearize Flux',Found ) ) THEN
    CALL ListAddNewLogical( Params,'Calculate Ce Sensitivity',.TRUE.)
  END IF

  
END SUBROUTINE ElectrolyteCons_Init


!-----------------------------------------------------------------------------
!> This is the conservation of species in electrolyte phase.
!> Eq. (3.6) in [1]. 
!------------------------------------------------------------------------------
SUBROUTINE ElectrolyteCons( Model,Solver,dt,Transient )
  !------------------------------------------------------------------------------
  USE DefUtils
  USE BatteryModule
  IMPLICIT NONE
  !------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: Transient
  !------------------------------------------------------------------------------
  ! Local variables
  !------------------------------------------------------------------------------
  TYPE(Element_t),POINTER :: Element
  REAL(KIND=dp) :: Norm, SSRelax
  INTEGER :: n, nb, nd, t, active, dim, iter, maxiter
  INTEGER :: VisitedTimes = 0
  LOGICAL :: Found, Newton, InitHandles
  TYPE(ValueList_t), POINTER :: Params 
  TYPE(Mesh_t), POINTER :: Mesh
  CHARACTER(*), PARAMETER :: Caller = 'ElectrolyteCons'
  TYPE(Variable_t), POINTER, SAVE :: SensVar
  !------------------------------------------------------------------------------

  CALL Info(Caller,'------------------------------------------------')
  CALL Info(Caller,'Solving concentration of electrolyte phase')
  CALL Info(Caller,'------------------------------------------------')
  
  CALL InitializeBattery()

  CALL DefaultStart()

  Mesh => GetMesh()
  Params => GetSolverParams()

  IF(( CurrentCoordinateSystem() /= Cartesian ) ) THEN
    CALL Fatal(Caller,'Only implemented for Cartesian coordinate system')
  END IF
  dim = CoordinateSystemDimension()

  maxiter = ListGetInteger( Params, &
      'Nonlinear System Max Iterations',Found,minv=1)
  IF(.NOT. Found ) maxiter = 1
  
  Newton = ListGetLogical( Params,'Linearize Flux',Found )  
  
  CeVar => Solver % Variable

  ! We may skip doing stuff on the solver for some iteration to let the potentials
  ! settle down. The concentrations are extremely sensitive to the potentials but
  ! not vice versa. 
  VisitedTimes = VisitedTimes + 1
  IF( VisitedTimes < GetInteger( Params,'Number of Passive Visits',Found ) ) THEN
    RETURN
  END IF

  IF( ListGetLogical( Params,'Use Solid Phase Relaxation',Found ) ) THEN 
    SSRelax = ListGetConstReal( Model % Simulation,'res: concentration relax')
    CALL ListAddConstReal( Params,'Nonlinear system relaxation factor',SSRelax )
  END IF
    
  
  ! Nonlinear iteration loop:
  !--------------------------
  DO iter=1,maxiter
    IF(maxiter>1) CALL Info(Caller,'Nonlinear system iteration: '//I2S(iter),Level=5)

    CALL VariableRange( CeVar, 7 )

    n = COUNT( CeVar % Values < 0 )
    IF( n > 0 ) THEN
      CALL Fatal(Caller,'Number of negative concentrations: '//I2S(n))
    END IF
      
    CALL ButlerVolmerUpdate(Solver)

    ! On the 1st iteration save the flux 
    IF( UseMeanFlux ) THEN
      Jli0 = JliVar % Values
    END IF

    IF( Newton ) THEN
      SensVar => VariableGet( Mesh % Variables,'dJli dCe')
      IF(.NOT. ASSOCIATED( SensVar ) ) THEN
        CALL Fatal('ButlerVolmer','Variable "dJli dCe" not present!')
      END IF
    END IF
        
    ! System assembly:
    !----------------
    CALL DefaultInitialize()

    CALL Info(Caller,'Performing bulk element assembly',Level=12)
    Active = GetNOFActive(Solver)
    InitHandles = .TRUE.
    DO t=1,Active
      Element => GetActiveElement(t)
      n  = GetElementNOFNodes(Element)
      nd = GetElementNOFDOFs(Element)
      nb = GetElementNOFBDOFs(Element)
      CALL LocalMatrix(  Element, n, nd+nb, nb, InitHandles )
    END DO
    CALL DefaultFinishBulkAssembly()

# 156 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BatterySolver/ElectrolyteCons.F90"
    
    CALL DefaultFinishBoundaryAssembly()
    CALL DefaultFinishAssembly()
    CALL DefaultDirichletBCs()

    ! And finally, solve:
    !--------------------       
    Norm = DefaultSolve()

    IF( DefaultConverged() ) EXIT

    CALL VariableRange( CeVar, 8)
     
  END DO

  CALL DefaultFinish()


CONTAINS


  !------------------------------------------------------------------------------
  ! Assembly of the matrix entries arising from the bulk elements. Not vectorized.
  !------------------------------------------------------------------------------
  SUBROUTINE LocalMatrix( Element, n, nd, nb, InitHandles )
    !------------------------------------------------------------------------------
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: n, nd, nb
    TYPE(Element_t), POINTER :: Element
    LOGICAL, INTENT(INOUT) :: InitHandles
    !------------------------------------------------------------------------------
    REAL(KIND=dp), ALLOCATABLE, SAVE :: Basis(:),dBasisdx(:,:), &
        ElemSource(:), ElemSource0(:), ElemSens(:), ElemCe(:)
    REAL(KIND=dp), ALLOCATABLE, SAVE :: MASS(:,:), STIFF(:,:), FORCE(:)
    REAL(KIND=dp) :: weight, DiffCe
    REAL(KIND=dp) :: SourceAtIp, EpsAtIp, DiffAtIp, SensAtIp, CeAtIp, DetJ, FluxCoeff
    LOGICAL :: Stat,Found, HaveSource
    INTEGER :: i,j,t,p,q,dim,m,allocstat
    TYPE(GaussIntegrationPoints_t) :: IP
    TYPE(Nodes_t), SAVE :: Nodes
    TYPE(ValueHandle_t), SAVE :: DiffCoeff_h, EpsCoeff_h
    TYPE(ValueList_t), POINTER :: Material
    !------------------------------------------------------------------------------

    ! This InitHandles flag might be false on threaded 1st call
    IF( InitHandles ) THEN
      CALL ListInitElementKeyword( DiffCoeff_h,'Material','Electrolyte Diffusion Coefficient')
      CALL ListInitElementKeyword( EpsCoeff_h,'Material','Electrolyte Volume Fraction')
      InitHandles = .FALSE.
    END IF

    Material => GetMaterial( Element )
    dim = CoordinateSystemDimension()
    IP = GaussPointsAdapt( Element ) 

    ! Allocate storage if needed
    IF (.NOT. ALLOCATED(Basis)) THEN
      m = Mesh % MaxElementDofs
      ALLOCATE(Basis(m), dBasisdx(m,3), MASS(m,m), STIFF(m,m), FORCE(m), &
          ElemSource(m), ElemSource0(m), ElemSens(m), ElemCe(m), &
          STAT=allocstat)      
      IF (allocstat /= 0) THEN
        CALL Fatal(Caller,'Local storage allocation failed')
      END IF
    END IF

    CALL GetElementNodes( Nodes, UElement=Element )

    ! Initialize
    MASS  = 0._dp
    STIFF = 0._dp
    FORCE = 0._dp

    HaveSource = ALL( JliVar % Perm( Element % NodeIndexes ) > 0 )
    IF( HaveSource ) THEN
      FluxCoeff = ElectrolyteFluxScaling( Material )

      IF( UseMeanFlux .OR. UseTimeAveFlux ) THEN
        ElemSource(1:n) = 0.5_dp * ( &
            JliVar % Values( JliVar % Perm( Element % NodeIndexes ) ) &
            + Jli0( JliVar % Perm( Element % NodeIndexes ) ) )
      ELSE
        ElemSource(1:n) = JliVar % Values( JliVar % Perm( Element % NodeIndexes ) )          
      END IF

      IF( Newton ) THEN
        ElemSens(1:n) = SensVar % Values( SensVar % Perm( Element % NodeIndexes ) )      
        ElemCe(1:n) = CeVar % Values( CeVar % Perm( Element % NodeIndexes ) )
      END IF
    END IF
    
    DO t=1,IP % n
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t), detJ, Basis, dBasisdx )
      Weight = IP % s(t) * DetJ

      ! electrolyte volume fraction
      EpsAtIp = ListGetElementReal( EpsCoeff_h, Basis, Element )            
      
       ! diffusion term
      DiffAtIp = ListGetElementReal( DiffCoeff_h, Basis, Element )
      
      ! If we multiply with EpsAtIp, the second term in PhiE solver can create difficulties
      ! So alternatively we can ignore the EpstAtIp to shorten the computational time and
      ! to increase stability
      IF ( ListGetLogical( Params,'Use Effective Diffusion', Found) ) THEN
        DiffCe = DiffAtIp * EpsAtIp
      ELSE
        DiffCe = DiffAtIp
      END IF

      STIFF(1:nd,1:nd) = STIFF(1:nd,1:nd) + Weight &       
          * DiffCe * MATMUL( dBasisdx(1:nd,:), TRANSPOSE( dBasisdx(1:nd,:) ) )
      
      ! time derivative term
      DO p=1,nd
        DO q=1,nd
          MASS(p,q) = MASS(p,q) + Weight * EpsAtIp * Basis(p) * Basis(q) 
        END DO
      END DO
      
      ! source  term
      IF( HaveSource ) THEN
        SourceAtIp = SUM( Basis(1:n) * ElemSource(1:n) )
        
        IF( Newton ) THEN
          SensAtIp = SUM( Basis(1:n) * ElemSens(1:n) )          
          IF( UseMeanFlux .OR. UseTimeAveFlux ) SensAtIp = 0.5_dp * SensAtIp
          CeAtIp = SUM( Basis(1:n) * ElemCe(1:n) ) 
          SourceAtIp = SourceAtIp - SensAtIp * CeAtIp 
          DO p=1,nd
            DO q=1,nd
              STIFF(p,q) = STIFF(p,q) - Weight * FluxCoeff * SensAtIp * &
                  Basis(p) * Basis(q)
            END DO
          END DO
        END IF
        FORCE(1:nd) = FORCE(1:nd) + Weight * FluxCoeff * SourceAtIP * Basis(1:nd)       
      END IF
      
    END DO
    
    IF(Transient) CALL Default1stOrderTime(MASS,STIFF,FORCE,UElement=Element)
    CALL CondensateP( nd-nb, nb, STIFF, FORCE )

    CALL DefaultUpdateEquations(STIFF,FORCE,UElement=Element )
    !------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrix
  !------------------------------------------------------------------------------

# 381 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BatterySolver/ElectrolyteCons.F90"
  
  !------------------------------------------------------------------------------
END SUBROUTINE ElectrolyteCons
!------------------------------------------------------------------------------
