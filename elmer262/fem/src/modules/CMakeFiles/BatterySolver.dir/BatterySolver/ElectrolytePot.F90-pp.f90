# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BatterySolver/ElectrolytePot.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BatterySolver/ElectrolytePot.F90"
!------------------------------------------------------------------------------
! For copyrights see the BatteryUtils.F90 file in this directory!
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!> Initial subroutine for the conservation of charge in electrolyte equation
!------------------------------------------------------------------------------
SUBROUTINE ElectrolytePot_init( Model,Solver,dt,Transient )
  !------------------------------------------------------------------------------
  USE DefUtils
  IMPLICIT NONE
  !------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: Transient
  !------------------------------------------------------------------------------
  CHARACTER(*), PARAMETER :: Caller = 'ElectrolytePot_init'
  TYPE(ValueList_t), POINTER :: Params
  LOGICAL :: Found
  INTEGER :: dim

  Params => GetSolverParams()
  dim = CoordinateSystemDimension()

  CALL ListAddNewString( Params,'Variable','phiE')

  IF( ListGetLogical( Params,'Linearize Flux',Found ) ) THEN
    CALL ListAddNewLogical( Params,'Calculate Phie Sensitivity',.TRUE.)
  END IF
  
END SUBROUTINE ElectrolytePot_Init
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!> Solves for the conservation of charge in electrolyte equation
!------------------------------------------------------------------------------ 
SUBROUTINE ElectrolytePot( Model,Solver,dt,Transient )
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
  REAL(KIND=dp) :: Norm
  INTEGER :: n, nb, nd, t, active, dim, iter, maxiter
  LOGICAL :: Found, InitHandles, Newton, CorrectDisbalance, TimeAveDiff
  TYPE(ValueList_t), POINTER :: Params
  TYPE(Mesh_t), POINTER :: Mesh
  CHARACTER(*), PARAMETER :: Caller = 'ElectrolytePot'
  TYPE(Variable_t), POINTER :: SensVar 
  REAL(KIND=dp) :: TotDiffFlux, AbsDiffFlux, TotArea
  REAL(KIND=dp), ALLOCATABLE, SAVE :: PhieWeight(:),PhieForce(:)
  REAL(KIND=dp) :: ForceAbsSum, ForceSum, WeightSum, coeff
  !------------------------------------------------------------------------------

  CALL Info(Caller,'------------------------------------------------')
  CALL Info(Caller,'Solving potential of electrolyte phase')
  CALL Info(Caller,'------------------------------------------------')

  CALL InitializeBattery()
  
  CALL DefaultStart()

  Mesh => GetMesh()
  Params => GetSolverParams() 

  dim = CoordinateSystemDimension() 

  maxiter = ListGetInteger( Params, &
      'Nonlinear System Max Iterations',Found,minv=1)
  IF(.NOT. Found ) maxiter = 1
  
  Newton = ListGetLogical( Params,'Linearize Flux',Found )
  
  CorrectDisbalance = ListGetLogical( Params,'Correct Source Disbalance',Found ) 

  TimeAveDiff = ListGetLogical( Params,'Use Time Average Diffusion',Found )

  IF( .NOT. ASSOCIATED( PhieVar, Solver % Variable ) ) THEN
    CALL Fatal(Caller,'This solver should own "Phie"')
  END IF

  IF(.NOT. ALLOCATED( PhieWeight ) ) THEN
    n = SIZE( PhieVar % Values ) 
    ALLOCATE( PhieWeight(n), PhieForce(n) )
  END IF
    
  ! Nonlinear iteration loop:
  !--------------------------
  DO iter=1,maxiter
    IF(maxiter>1) CALL Info(Caller,'Nonlinear system iteration: '//I2S(iter),Level=5)
    
    ! Update flux from Butler-Volmer equation
    !------------------------------------------------------------------    
    CALL ButlerVolmerUpdate(Solver)

    IF( Newton ) THEN
      SensVar => VariableGet( Mesh % Variables,'dJli dPhie')
      IF(.NOT. ASSOCIATED( SensVar ) ) THEN
        CALL Fatal(Caller,'Variable "dJli dPhie" not present!')
      END IF
    END IF
    
    ! System assembly:
    !----------------
    CALL DefaultInitialize()

    CALL Info(Caller,'Performing bulk element assembly',Level=12)
    Active = GetNOFActive(Solver) 
    InitHandles = .TRUE.

    PhieForce = 0.0_dp
    PhieWeight = 0.0_dp
    TotDiffFlux = 0.0_dp
    AbsDiffFlux = 0.0_dp
    TotArea = 0.0_dp

    DO t=1,Active
      Element => GetActiveElement(t)
      n  = GetElementNOFNodes(Element) 
      nd = GetElementNOFDOFs(Element) 
      nb = GetElementNOFBDOFs(Element)
      CALL LocalMatrix(  Element, n, nd+nb, nb, InitHandles )
    END DO
    CALL DefaultFinishBulkAssembly()

    
# 151 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BatterySolver/ElectrolytePot.F90"

    IF( InfoActive(7) .OR. CorrectDisbalance ) THEN        
      ForceSum = SUM( PhieForce )
      ForceAbsSum = SUM( ABS( PhieForce ) )    
      PRINT *,'Phie Source disbalance:',ForceSum, ForceAbsSum, ForceSum / ForceAbsSum
    END IF
      
    IF( CorrectDisbalance ) THEN
      WeightSum = SUM( PhieWeight )
      coeff = -ForceSum / WeightSum
      Solver % Matrix % Rhs = Solver % Matrix % Rhs + coeff * PhieWeight
    END IF      
    
    CALL DefaultFinishBoundaryAssembly()  
    CALL DefaultFinishAssembly() 

    ! BCs are always natural
    ! CALL DefaultDirichletBCs() 

    
    ! And finally, solve:
    !--------------------
    Norm = DefaultSolve()

    CALL VariableRange( PhieVar, 8 )
    
    IF( Solver % Variable % NonlinConverged == 1 ) EXIT
    
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
    REAL(KIND=dp), ALLOCATABLE, SAVE :: Basis(:),dBasisdx(:,:),ddBasisddx(:,:,:), &
        MASS(:,:), STIFF(:,:), FORCE(:), ElemSource(:), ElemPhie(:), ElemDiff(:), &
        ElemSens(:), ElemCe(:), NewtonFORCE(:)
    REAL(KIND=dp) :: weight, Kappa, SourceAtIp, PhieAtIp, SensAtIp, CeAtIp, DetJ, &
        GradLogCe(3), DiffCoeff
    LOGICAL :: Stat,Found,HaveSource
    LOGICAL, SAVE :: DoDiffusion, QuadDiffusion
    INTEGER :: i,j,t,p,q,dim,m,allocstat,ElemCode
    TYPE(GaussIntegrationPoints_t) :: IP
    TYPE(Nodes_t), SAVE :: Nodes
    TYPE(ValueList_t), POINTER :: Material
    !------------------------------------------------------------------------------

    dim = CoordinateSystemDimension()
    IP = GaussPointsAdapt( Element ) 

    ! Allocate storage if needed
    IF (.NOT. ALLOCATED(Basis)) THEN
      m = Mesh % MaxElementDofs
      ALLOCATE(Basis(m), dBasisdx(m,3), ddBasisddx(m,3,3), MASS(m,m), STIFF(m,m), &
          FORCE(m), NewtonForce(m), ElemSource(m), ElemPhie(m), ElemDiff(m), ElemCe(m), &
          ElemSens(m), STAT=allocstat)      
      IF (allocstat /= 0) THEN
        CALL Fatal(Caller,'Local storage allocation failed')
      END IF
    END IF

    IF( InitHandles ) THEN
      ! To allow toggling of this effect on/off
      DoDiffusion = .NOT. ListGetLogical(Params,'Ignore Electrolyte Diffusion',Found)
      QuadDiffusion = ListGetLogical(Params,'Quadratic Electrolyte Diffusion',Found)

      IF( QuadDiffusion ) THEN
        ElemCode = Mesh % Elements(1) % TYPE % ElementCode
        IF( ElemCode == 202 .OR. ElemCode == 303 .OR. ElemCode == 404 ) THEN
          CALL Fatal(Caller,'Quadratic mesh required for quadratic diffusion!')
        END IF
      END IF

      InitHandles = .FALSE.
    END IF

    ! Do we have source terms for this element?
    HaveSource = ALL( JliVar % Perm( Element % NodeIndexes ) > 0 )
    IF( HaveSource ) THEN
      ElemSource(1:n) = JliVar % Values( JliVar % Perm( Element % NodeIndexes ) )
      IF( Newton ) THEN
        ElemSens(1:n) = SensVar % Values( SensVar % Perm( Element % NodeIndexes ) )
        ElemPhie(1:n) = PhieVar % Values( PhieVar % Perm( Element % NodeIndexes ) )
      END IF
    END IF
      
    ! Electrolyte concentration at nodes
    IF( DoDiffusion ) THEN
      IF( UseTimeAveDiff ) THEN
        ElemCe(1:n) = 0.5_dp * ( & 
            CeVar % Values( CeVar % Perm( Element % NodeIndexes ) ) + &
            CeVar % PrevValues( CeVar % Perm( Element % NodeIndexes ), 1 ) )
      ELSE
        ElemCe(1:n) = CeVar % Values( CeVar % Perm( Element % NodeIndexes ) )
      END IF
    END IF
        
    CALL GetElementNodes( Nodes, UElement=Element )
    Material => GetMaterial(Element)
    
    ! Initialize    
    STIFF = 0._dp
    FORCE = 0._dp
    NewtonForce = 0.0_dp
    
    DO t=1,IP % n
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      IF( QuadDiffusion ) THEN
        ! If we do not use weak for of the 2nd derivative we need to evaluate
        ! the 2nd derivative also. Note that this requires 2nd order elements!
        stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
            IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .TRUE. )
      ELSE
        stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
            IP % W(t), detJ, Basis, dBasisdx )
      END IF
      Weight = IP % s(t) * DetJ

      ! Getting conductivity term + assembly of the K matrix
      CeAtIp = SUM( Basis(1:n) * ElemCe(1:n) )
      Kappa = EffIonConductivity(Material, CeAtIp ) 

      TotArea = TotArea + Weight

      STIFF(1:nd,1:nd) = STIFF(1:nd,1:nd) + Weight * &
          Kappa * MATMUL( dBasisdx(1:nd,:), TRANSPOSE( dBasisdx(1:nd,:) ) )
      
      ! Source term at integration point (j_li)
      ! Electrolyte uses positive sign with the source as in (3.12) of [1]
      ! Note that the sign of DivGrad gets changed for weak form. 
      IF( HaveSource ) THEN
        SourceAtIP = SUM(Basis(1:n)*ElemSource(1:n))
        FORCE(1:nd) = FORCE(1:nd) + Weight * SourceAtIP * Basis(1:nd)
      END IF
        
      ! This could be optional when testing for different formulations
      IF( DoDiffusion ) THEN
        DiffCoeff = EffDiffConductivity(Material, CeAtIp ) 
        IF( QuadDiffusion ) THEN
          DO i=1,dim
            FORCE(1:nd) = FORCE(1:nd) + &
                Basis(1:n) * Weight * DiffCoeff * SUM( ddBasisddx(1:nd,i,i) * LOG( ElemCe(1:nd) ) )
          END DO
        ELSE
          GradLogCe = 0.0_dp
          DO i=1,dim
            GradLogCe(i) = SUM( dBasisdx(1:n,i) * LOG( ElemCe(1:n) ) )
          END DO
          DO i=1,dim
            FORCE(1:nd) = FORCE(1:nd) - &
                Weight * dBasisdx(1:nd,i) * DiffCoeff * GradLogCe(i)
          END DO
        END IF
          
        !DO p=1,nd
        !  ElemDiff(p) = -DiffCoeff * SUM( dBasisdx(p,1:dim) * GradLogCe(1:dim) )
        !END DO        
        !FORCE(1:nd) = FORCE(1:nd) + Weight * ElemDiff(1:nd)
      END IF
      
      IF( HaveSource .AND. Newton ) THEN
        SensAtIp = SUM( Basis(1:n) * ElemSens(1:n) )
        PhieAtIp = SUM( Basis(1:n) * ElemPhie(1:n) ) 
        DO p=1,nd
          DO q=1,nd
            STIFF(p,q) = STIFF(p,q) - Weight * SensAtIp * Basis(p) * Basis(q)
          END DO
          NewtonFORCE(p) = NewtonFORCE(p) - Weight * SensAtIp * PhieAtIp * Basis(p)  
        END DO
      END IF
      
      PhieWeight( PhieVar % Perm(Element % NodeIndexes) ) = &
          PhieWeight( PhieVar % Perm(Element % NodeIndexes) ) + Weight * Basis(1:nd)
    END DO

    ! This is just the pure r.h.s. vector without newton linearization
    PhieForce( PhieVar % Perm(Element % NodeIndexes) ) = &
        PhieForce( PhieVar % Perm(Element % NodeIndexes) ) + FORCE(1:nd)
    
    IF( Newton ) THEN
      FORCE(1:nd) = FORCE(1:nd) + NewtonForce(1:nd)
    END IF
    
    CALL DefaultUpdateEquations(STIFF,FORCE,UElement=Element )

    !---------------------------
  END SUBROUTINE LocalMatrix
  !---------------------------

# 413 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/modules/BatterySolver/ElectrolytePot.F90"
  
  !-------------------------------
END SUBROUTINE ElectrolytePot
!------------------------------------------------------------------------------
