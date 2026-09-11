# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
!
# 23 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
!
! ******************************************************************************
! *
! *  Authors: Joe Todd
! *
! ****************************************************************************/

!> \ingroup ElmerLib
!> \{

MODULE MeshRemeshing

USE Types
USE Lists
USE Messages
USE MeshUtils, ONLY : PrepareMesh, MarkSharpEdges, MarkSharpNodes, GetDefs
USE MeshPartition
USE SparIterComm

IMPLICIT NONE






# 70 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"





INTEGER, PARAMETER :: ElmerBCOffset = 1000

CONTAINS

!============================================
!============================================
!            MMG3D SUBROUTINES
!============================================
!============================================

  
SUBROUTINE Set_MMG3D_Mesh(Mesh, Parallel, EdgePairs, PairCount, Solver)

  TYPE(Mesh_t), POINTER :: Mesh
  LOGICAL :: Parallel
  INTEGER, ALLOCATABLE, OPTIONAL :: EdgePairs(:,:)
  INTEGER, OPTIONAL :: PairCount
  TYPE(Solver_t), POINTER, OPTIONAL :: Solver
  
# 342 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
  CALL Fatal('Set_MMG3D_Mesh',&
        'Remeshing utility MMG3D has not been installed')


END SUBROUTINE Set_MMG3D_Mesh


SUBROUTINE Check_Parameters_Obsolete(SolverParams)

  TYPE(ValueList_t), POINTER :: SolverParams
  LOGICAL :: Checked = .FALSE.

  IF(Checked) RETURN
  
  IF( ListCheckPrefix( SolverParams,'RemeshMMG3D') ) THEN
    CALL Fatal('Check_Parameters_Obsolete','Use "MMG" as prefix instead of "RemeshMMG3D"')
  END IF
  CALL ListObsoleteFatal(SolverParams,'hmin','MMG hmin')
  CALL ListObsoleteFatal(SolverParams,'hmax','MMG hmax')
  CALL ListObsoleteFatal(SolverParams,'hsiz','MMG hsiz')
  CALL ListObsoleteFatal(SolverParams,'hausd','MMG hausd')
  CALL ListObsoleteFatal(SolverParams,'hgrad','MMG hgrad')
  CALL ListObsoleteFatal(SolverParams,'verbosity','MMG verbosity')
  CALL ListObsoleteFatal(SolverParams,'angle detection','MMG angle detection')
  CALL ListObsoleteFatal(SolverParams,'no angle detection','MMG no angle detection')
  CALL ListObsoleteFatal(SolverParams,'increase memory','MMG increase memory')
  CALL ListObsoleteFatal(SolverParams,'no insert','MMG noinsert')
  CALL ListObsoleteFatal(SolverParams,'no swap','MMG no swap')
  CALL ListObsoleteFatal(SolverParams,'no move','MMG no move')
  CALL ListObsoleteFatal(SolverParams,'no surf','MMG no surf')

  Checked = .TRUE.
  
END SUBROUTINE Check_Parameters_Obsolete
  
  

SUBROUTINE Set_MMG3D_Parameters(SolverParams, ReTrial)

  TYPE(ValueList_t), POINTER :: SolverParams
  LOGICAL, OPTIONAL :: ReTrial
  
# 541 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
     CALL Fatal('Set_MMG3D_Parameters',&
        'Remeshing utility MMG3D has not been installed')

   END SUBROUTINE Set_MMG3D_Parameters

   
SUBROUTINE Set_PMMG_Parameters(SolverParams, ReTrial )

  TYPE(ValueList_t), POINTER :: SolverParams
  LOGICAL, OPTIONAL :: ReTrial
  
# 708 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
  CALL Fatal('Set_PMMG_Parameters',&
      'Remeshing utility MMG3D has not been installed')

END SUBROUTINE Set_PMMG_Parameters
   

SUBROUTINE Get_MMG3D_Mesh(NewMesh, Parallel, FixedNodes, FixedElems, Calving)

  !------------------------------------------------------------------------------
  TYPE(Mesh_t), POINTER :: NewMesh
  LOGICAL :: Parallel
  LOGICAL, OPTIONAL, ALLOCATABLE :: FixedNodes(:), FixedElems(:)
  LOGICAL, OPTIONAL :: Calving
  !------------------------------------------------------------------------------

# 1071 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
     CALL Fatal('Get_MMG3D_Mesh',&
        'Remeshing utility MMG3D has not been installed')


END SUBROUTINE Get_MMG3D_Mesh

! Subroutine to negotiate new global node numbers between partitions
! as a necessary precursor to repartitioning the mesh.
! Expects to receive OldMesh with valid GlobalDOFs, and new mesh 
! in which all GlobalDOFs are either present in the OldMesh, or set to zero.
! We allow here that each partition may have any number of nodes (inc. zero)
! Assumes that NewMesh doesn't have any nodes which are both *shared* and *unmarked*
!-----------------------------------------------------------------------------------
SUBROUTINE RenumberGDOFs(OldMesh,NewMesh)
  TYPE(Mesh_t), POINTER :: OldMesh, NewMesh
  !----------------------
  INTEGER :: i,j,k,n,counter, OldNN, NewNN, nglobal_pool, nlocal_pool,&
       ierr, my_maxgdof, mingdof, maxgdof, request,unused,&
       Need, PNeed(ParEnv % PEs), pnlocal_pool(ParEnv % PEs), disps(ParEnv % PEs), &
       PNeed_tot
  INTEGER, ALLOCATABLE :: old_gdofs(:), new_gdofs(:), global_pool(:),&
       local_pool(:), work_int(:), GDOF_remap(:), send_to(:)
  INTEGER, POINTER :: ngdof_ptr(:), ogdof_ptr(:)
  LOGICAL :: Root, Debug = .FALSE.
  LOGICAL, ALLOCATABLE :: AvailGDOF(:), pool_duplicate(:), im_using(:), used(:)
  CHARACTER(*), PARAMETER :: FuncName="RenumberGDOFs"

  Root = ParEnv % MyPE == 0
  OldNN = OldMesh % NumberOfNodes
  NewNN = NewMesh % NumberOfNodes

  ngdof_ptr => NewMesh % ParallelInfo % GlobalDOFs
  ogdof_ptr => OldMesh % ParallelInfo % GlobalDOFs

  ALLOCATE(old_gdofs(OldNN), &
       new_gdofs(NewNN), &
       AvailGDOF(OldNN))

  AvailGDOF = .FALSE.

  old_gdofs = ogdof_ptr
  CALL Sort(OldNN,old_gdofs)
  new_gdofs = ngdof_ptr
  CALL Sort(NewNN,new_gdofs)

  my_maxgdof = old_gdofs(oldNN)
  CALL MPI_ALLREDUCE( my_maxgdof, maxgdof, 1, MPI_INTEGER, MPI_MAX, ELMER_COMM_WORLD, ierr)

  IF(Debug) PRINT *,ParEnv % MyPE,' debug max gdof :', maxgdof

  !Locally check the consistency of the old mesh
  DO i=1,OldNN-1
    IF(old_gdofs(i) == old_gdofs(i+1)) &
         CALL Fatal(FuncName,"OldMesh has duplicate GlobalDOFs")
  END DO
  IF(ANY(old_gdofs <= 0)) CALL Fatal(FuncName,"OldMesh has at least 1 GlobalDOFs <= 0")

  !Determine locally which GlobalDOFs are available for assignment
  DO i=1, OldNN
    k = SearchI(NewNN, new_gdofs, old_gdofs(i))
    IF(k == 0) AvailGDOF(i) = .TRUE.
  END DO

  nlocal_pool = COUNT(AvailGDOF)
  ALLOCATE(local_pool(COUNT(AvailGDOF)))
  local_pool = PACK(old_gdofs,AvailGDOF)
  CALL Assert(ALL(local_pool > 0), "RenumberGDOFs", "Programming error: some local pool <= 0")

  !Gather pool of available global nodenums to root
  !--------------------------------------
  !Note: previously allowed partitions to fill from local pool at this stage
  !but this assumes that no previously shared nodes are destroyed. Not necessarily
  !the case.

  CALL MPI_GATHER(nlocal_pool, 1, MPI_INTEGER, pnlocal_pool, 1, &
       MPI_INTEGER, 0, ELMER_COMM_WORLD, ierr)

  IF(Root) THEN
    IF(Debug) PRINT *,'pnlocal_pool: ',pnlocal_pool
    nglobal_pool = SUM(pnlocal_pool)
    ALLOCATE(global_pool(nglobal_pool), pool_duplicate(nglobal_pool))
    pool_duplicate = .FALSE.
    disps(1) = 0
    DO i=2,ParEnv % PEs
      disps(i) = disps(i-1) + pnlocal_pool(i-1)
    END DO
  END IF

  CALL MPI_GatherV(local_pool, nlocal_pool, MPI_INTEGER, global_pool, &
       pnlocal_pool,disps, MPI_INTEGER, 0, ELMER_COMM_WORLD, ierr)

  DEALLOCATE(local_pool)

  !Sort & remove duplicates from global pool
  IF(Root) THEN
    CALL Sort(nglobal_pool, global_pool)
    DO i=2,nglobal_pool
      IF(global_pool(i) == global_pool(i-1)) pool_duplicate(i) = .TRUE.
    END DO
    nglobal_pool = COUNT(.NOT. pool_duplicate)

    ALLOCATE(work_int(nglobal_pool))
    work_int = PACK(global_pool, .NOT. pool_duplicate)

    DEALLOCATE(global_pool)
    CALL MOVE_ALLOC(work_int, global_pool)

    IF(Debug) THEN
      PRINT *,'Removed ',COUNT(pool_duplicate),' duplicate global pool entries'
      PRINT *,'new global pool: ',global_pool
    END IF
  END IF

  !Now we have a pool of nodenums (global_pool) no longer
  !used by each partition, but we need to check for those 
  !nodes which were simply passed from one partition to another
  !in OldMesh -> NewMesh
  CALL MPI_BCAST(nglobal_pool,1, MPI_INTEGER, 0, ELMER_COMM_WORLD, ierr)
  IF(.NOT. Root) ALLOCATE(global_pool(nglobal_pool))
  ALLOCATE(im_using(nglobal_pool))
  im_using = .FALSE.
  CALL MPI_BCAST(global_pool,nglobal_pool, MPI_INTEGER, 0, ELMER_COMM_WORLD, ierr)

  DO i=1, nglobal_pool
    k = SearchI(NewNN, new_gdofs, global_pool(i))
    IF(k /= 0) im_using(i) = .TRUE.
    IF(k /= 0 .AND. Debug) PRINT *,ParEnv % MyPE,' using ',global_pool(i),' from global pool'
  END DO

  !Logical reduction to determine which global dofs are actually in use
  IF(Root) ALLOCATE(used(nglobal_pool))
  CALL MPI_REDUCE(im_using, used, nglobal_pool, MPI_LOGICAL, MPI_LOR, 0, ELMER_COMM_WORLD, ierr)

  IF(ROOT) THEN
    IF(Debug) PRINT *, COUNT(used),' are in use of ',nglobal_pool
    ALLOCATE(work_int(COUNT(.NOT. used)))
    work_int = PACK(global_pool, .NOT. used)
    DEALLOCATE(global_pool)
    CALL MOVE_ALLOC(work_int, global_pool)
    nglobal_pool = SIZE(global_pool)
  ELSE
    DEALLOCATE(global_pool)
  END IF

  !Gather how many global nodenums required by each partition
  Need = COUNT(ngdof_ptr == 0)
  CALL MPI_GATHER(Need, 1, MPI_INTEGER, PNeed, 1, MPI_INTEGER, &
       0, ELMER_COMM_WORLD, ierr)

  !Either: 
  ! SUM(PNeed) > nglobal_pool : generate additional globalDOFs
  ! SUM(PNeed) < nglobal_pool : delete excess globalDOFs
  ! SUM(PNeed) == nglobal_pool : all good (rare)

  IF(Root) THEN
    PNeed_tot = SUM(PNeed)

    IF(PNeed_tot > nglobal_pool) THEN

      ALLOCATE(work_int(PNeed_tot))
      work_int = 0
      work_int(1:nglobal_pool) = global_pool
      DO i=1, PNeed_tot - nglobal_pool
        work_int(nglobal_pool + i) = maxgdof + i
      END DO
      DEALLOCATE(global_pool)
      CALL MOVE_ALLOC(work_int, global_pool)
      nglobal_pool = PNeed_tot
    END IF

    !Mark global dofs to send to each part
    !-1 means excess (to be destroyed)
    ALLOCATE(send_to(nglobal_pool))
    send_to = -1 !default
    counter = 1
    DO i=1,ParEnv % PEs
      send_to(counter:counter+PNeed(i)-1) = i-1
      counter = counter + PNeed(i)
    END DO
  END IF

  !Set up iRECV if required
  IF(Need > 0) THEN
    ALLOCATE(local_pool(Need))
    CALL MPI_iRECV(local_pool,Need,MPI_INTEGER,0,1001,&
       ELMER_COMM_WORLD, request, ierr)
  END IF

  !Root sends out nodes from pool
  IF(Root) THEN
    IF(Debug) PRINT *,'Pneed: ',PNeed
    counter = 1
    DO i=1,ParEnv % PEs
      IF(PNeed(i) <= 0) CYCLE

      IF(ANY(send_to(counter:counter+PNeed(i)-1) /= i-1)) &
           CALL Fatal(FuncName, "Programming error in send pool")

      CALL MPI_SEND(global_pool(counter:counter+PNeed(i)-1),PNeed(i),&
           MPI_INTEGER, i-1, 1001, ELMER_COMM_WORLD, ierr)

      counter = counter + PNeed(i)
    END DO
  END IF

  IF(Need > 0) CALL MPI_Wait(request, MPI_STATUS_IGNORE, ierr)

  !Fill from pool as required
  IF(Need > 0) THEN
    counter = 0
    DO i=1,NewNN
      IF(ngdof_ptr(i) == 0) THEN
        counter = counter + 1
        ngdof_ptr(i) = local_pool(counter)
      END IF
    END DO
  END IF


  !Root packs and sends unused gdofs
  IF(Root) THEN
    unused = COUNT(send_to == -1)
    IF(Debug) PRINT *,ParEnv % MyPE,' unused: ',unused

    ALLOCATE(work_int(unused))
    work_int = PACK(global_pool,  send_to == -1)
    DEALLOCATE(global_pool)
    CALL MOVE_ALLOC(work_int, global_pool)

    IF(Debug) THEN
      PRINT *,' unused, size(global_pool): ', unused, SIZE(global_pool)
      PRINT *,'Final global pool: ',global_pool
    END IF
  END IF

  CALL MPI_BCAST(unused,1, MPI_INTEGER, 0, ELMER_COMM_WORLD, ierr)

  IF(.NOT. Root) THEN
    ALLOCATE(global_pool(unused))
  END IF

  CALL MPI_BCAST(global_pool,unused,MPI_INTEGER, 0, ELMER_COMM_WORLD, ierr)

  !Renumber GDOFs to ensure contiguity if required
  IF(unused > 0) THEN
    IF(Debug) PRINT *,ParEnv % MyPE,' final global pool: ',global_pool

    MaxGDOF = MAXVAL(ngdof_ptr)
    MinGDOF = MINVAL(ngdof_ptr)
    IF(MinGDOF <= 0) CALL Fatal(FuncName, "Programming error: at least one gdof == 0")

    new_gdofs = ngdof_ptr
    CALL Sort(NewNN, new_gdofs)

    ALLOCATE(GDOF_remap(MinGDOF:MaxGDOF))
    DO i=1,NewNN
        GDOF_remap(new_gdofs(i)) = new_gdofs(i) - SearchIntPosition(global_pool, new_gdofs(i))
        IF(Debug) PRINT *,ParEnv % MyPE,' debug gdof map: ',new_gdofs(i), &
             SearchIntPosition(global_pool, new_gdofs(i)), GDOF_remap(new_gdofs(i))
    END DO

    ngdof_ptr = GDOF_remap(ngdof_ptr)
  END IF

END SUBROUTINE RenumberGDOFs

! Because elements aren't shared, renumbering is easier
! Simply number contiguously in each partition
! NOTE: won't work for halo elems
!---------------------------------------------------------
SUBROUTINE RenumberGElems(Mesh)
  TYPE(Mesh_t), POINTER :: Mesh
  !---------------------------------
  INTEGER :: i,NElem,MyStart,ierr
  INTEGER, ALLOCATABLE :: PNElem(:)

  NElem = Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements
  ALLOCATE(PNElem(ParEnv % PEs))

  CALL MPI_ALLGATHER(NElem,1,MPI_INTEGER, PNElem, 1, MPI_INTEGER, ELMER_COMM_WORLD, ierr)

  MyStart = SUM(PNElem(1:ParEnv % MyPE))
  DO i=1,NElem
    Mesh % Elements(i) % GElementIndex = MyStart + i
  END DO

END SUBROUTINE RenumberGElems


! Based on a previous mesh with valid nodal parallelinfo (% GInterface & % NeighbourList)
! map that info onto NewMesh which shares at least some GlobalDOFs. Intended use is
! to enable reconnection of a parallel mesh part which has been remeshed internally, but
! whose partition boundaries remain as they were. e.g. CalvingRemeshMMG.F90
!---------------------------------------------------------------------------------------------
SUBROUTINE MapNewParallelInfo(OldMesh, NewMesh)
  TYPE(Mesh_t), POINTER :: OldMesh, NewMesh
  !---------------------------------
  INTEGER, ALLOCATABLE :: GtoNewLMap(:)
  INTEGER :: i,k,n,MaxNGDof, MinNGDof
  CHARACTER(*), PARAMETER :: FuncName="MapNewBCInfo"
  
  MinNGDof = HUGE(MinNGDof)
  MaxNGDof = 0
  DO i=1,NewMesh % NumberOfNodes
    k = NewMesh % ParallelInfo % GlobalDOFs(i)
    IF(k == 0) CYCLE
    MinNGDof = MIN(k,MinNGDof)
    MaxNGDof = MAX(k, MaxNGDof)
  END DO

  ALLOCATE(GtoNewLMap(MinNGDof:MaxNGDof))
  GtoNewLMap = 0

  DO i=1,NewMesh % NumberOfNodes
    k = NewMesh % ParallelInfo % GlobalDOFs(i)
    IF(k == 0) CYCLE
    GtoNewLMap(k) = i
  END DO

  DO i=1,OldMesh % NumberOfNodes
    IF(OldMesh % ParallelInfo % GInterface(i)) THEN
      k = OldMesh % ParallelInfo % GlobalDOFs(i)
      IF(k < LBOUND(GToNewLMap,1) .OR. k > UBOUND(GToNewLMap,1)) THEN
        CALL Warn(FuncName, "Interface node from OldMesh missing in NewMesh")
        CYCLE
      ELSEIF(GToNewLMap(k) == 0) THEN
        CALL Warn(FuncName, "Interface node from OldMesh missing in NewMesh")
        CYCLE
      END IF
      k = GToNewLMap(k)
      NewMesh % ParallelInfo % GInterface(k) = .TRUE.

      n = SIZE(OldMesh % ParallelInfo % Neighbourlist(i) % Neighbours)
      IF(ASSOCIATED(NewMesh % ParallelInfo % Neighbourlist(k) % Neighbours)) &
           DEALLOCATE(NewMesh % ParallelInfo % Neighbourlist(k) % Neighbours)
      ALLOCATE(NewMesh % ParallelInfo % Neighbourlist(k) % Neighbours(n))
      NewMesh % ParallelInfo % Neighbourlist(k) % Neighbours = &
           OldMesh % ParallelInfo % Neighbourlist(i) % Neighbours
    END IF
  END DO

  DO i=1,NewMesh % NumberOfNodes
    IF(.NOT. ASSOCIATED(NewMesh % ParallelInfo % Neighbourlist(i) % Neighbours)) THEN
      ALLOCATE(NewMesh % ParallelInfo % Neighbourlist(i) % Neighbours(1))
      NewMesh % ParallelInfo % Neighbourlist(i) % Neighbours(1) = ParEnv % MyPE
    END IF
  END DO
END SUBROUTINE MapNewParallelInfo


! A subroutine for a 3D mesh (in serial) with MMG3D
! Inputs:
!   InMesh - the initial mesh
!   Metric - 2D real array specifying target metric
!   NodeFixed, ElemFixed - Optional mask to specify 'required' entities
! Output:
!   OutMesh - the improved mesh
!----------------------------------------------------------------------------------
SUBROUTINE RemeshMMG3D(Model, InMesh,OutMesh,EdgePairs,PairCount,&
    NodeFixed,ElemFixed,Params,Hvar,Solver,Success)

  TYPE(Model_t) :: Model
  TYPE(Mesh_t), POINTER :: InMesh, OutMesh
  TYPE(ValueList_t), POINTER, OPTIONAL :: Params
  LOGICAL, ALLOCATABLE, OPTIONAL :: NodeFixed(:), ElemFixed(:)
  INTEGER, ALLOCATABLE, OPTIONAL :: EdgePairs(:,:)
  INTEGER, OPTIONAL :: PairCount
  TYPE(Variable_t), POINTER, OPTIONAL :: HVar
  TYPE(Solver_t), POINTER, OPTIONAL :: Solver
  LOGICAL :: Success
  !-----------
  TYPE(Mesh_t), POINTER :: WorkMesh
  TYPE(ValueList_t), POINTER :: FuncParams, Material
  TYPE(Variable_t), POINTER :: TimeVar, MMGVar
  TYPE(Element_t), POINTER :: Element
  REAL(KIND=dp), ALLOCATABLE :: TargetLength(:,:), Metric(:,:)
  REAL(KIND=dp), POINTER :: WorkReal(:,:,:) => NULL(), hminarray(:,:) => NULL(),&
       hausdarray(:,:) => NULL()
  REAL(KIND=dp) :: hsiz(3),hmin,hmax,hgrad,hausd,RemeshMinQuality,Quality
  INTEGER :: i,j,MetricDim,NNodes,NBulk,NBdry,ierr,SolType,body_offset,&
       nBCs,NodeNum(1), MaxRemeshIter, mmgloops, &
       NVerts, NTetras, NPrisms, NTris, NQuads, NEdges, Counter, Time
  INTEGER, ALLOCATABLE :: TetraQuality(:)
  LOGICAL :: Debug, Parallel, AnisoFlag, Found, SaveMMGMeshes, SaveMMGSols, &
      UseHvar, UseTargetLength, MultipleInputs
  LOGICAL, ALLOCATABLE :: RmElement(:)
  CHARACTER(:), ALLOCATABLE :: FuncName, &
        premmg_meshfile, mmg_meshfile, premmg_solfile, mmg_solfile
  CHARACTER(MAX_NAME_LEN) :: MeshName, SolName
  SAVE :: WorkReal

# 1788 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
  CALL Fatal(FuncName, "Remeshing utility MMG3D has not been installed")


END SUBROUTINE RemeshMMG3D

!A subroutine for a 3D mesh (in parallel) with ParMMG3D
!Inputs:
!   InMesh - the initial mesh
!   Metric - 2D real array specifying target metric
!   NodeFixed, ElemFixed - Optional mask to specify 'required' entities
!Output:
!   OutMesh - the improved mesh
!
SUBROUTINE SequentialRemeshParMMG(Model, InMesh,OutMesh,Boss,EdgePairs,PairCount,&
    NodeFixed,ElemFixed,Params)

 TYPE(Model_t) :: Model
  TYPE(Mesh_t), POINTER :: InMesh, OutMesh
  TYPE(ValueList_t), POINTER :: Params
  LOGICAL :: Boss
  LOGICAL, ALLOCATABLE, OPTIONAL :: NodeFixed(:), ElemFixed(:)
  INTEGER, ALLOCATABLE, OPTIONAL :: EdgePairs(:,:)
  INTEGER, OPTIONAL :: PairCount
  LOGICAL :: Success
  !-----------
  TYPE(Mesh_t), POINTER :: WorkMesh
  TYPE(ValueList_t), POINTER :: FuncParams, Material
  TYPE(Variable_t), POINTER :: TimeVar, MMGVar
  TYPE(Element_t), POINTER :: Element
  REAL(KIND=dp), ALLOCATABLE :: TargetLength(:,:), Metric(:,:),hminarray(:),hausdarray(:)
  REAL(KIND=dp), POINTER :: WorkReal(:,:,:) => NULL() 
  REAL(KIND=dp) :: hsiz(3),hmin,hmax,hgrad,hausd,RemeshMinQuality,Quality
  INTEGER :: i,j,MetricDim,NNodes,NBulk,NBdry,ierr,SolType,body_offset,&
       nBCs,NodeNum(1), MaxRemeshIter, mmgloops, &
       NVerts, NTetras, NPrisms, NTris, NQuads, NEdges, Counter, Time
  INTEGER, ALLOCATABLE :: TetraQuality(:)
  LOGICAL :: Debug, Parallel, AnisoFlag, Found, SaveMMGMeshes, SaveMMGSols
  LOGICAL, ALLOCATABLE :: RmElement(:)
  CHARACTER(:), ALLOCATABLE :: MeshName, SolName, &
        premmg_meshfile, mmg_meshfile, premmg_solfile, mmg_solfile
  CHARACTER(*), PARAMETER :: FuncName = "SequentialRemeshParMMG3D"
  SAVE :: WorkReal 

# 2105 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
  CALL Fatal(FuncName, "Remeshing utility PMMG has not been installed")


END SUBROUTINE SequentialRemeshParMMG


SUBROUTINE Set_ParMMG_Mesh(Mesh, Parallel, EdgePairs, PairCount, FreezeInternalArg)

  TYPE(Mesh_t), POINTER :: Mesh
  LOGICAL :: Parallel
  LOGICAL, OPTIONAL :: FreezeInternalArg
  INTEGER, ALLOCATABLE, OPTIONAL :: EdgePairs(:,:)
  INTEGER, OPTIONAL :: PairCount

# 2337 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
     CALL Fatal('Set_ParMMG_Mesh',&
        'Remeshing utility ParMMG has not been installed')


END SUBROUTINE Set_ParMMG_Mesh


SUBROUTINE Get_ParMMG_Mesh(NewMesh, Parallel, FixedNodes, FixedElems, Calving)

  !------------------------------------------------------------------------------
  TYPE(Mesh_t), POINTER :: NewMesh
  LOGICAL :: Parallel
  LOGICAL :: Calving
  LOGICAL, OPTIONAL, ALLOCATABLE :: FixedNodes(:), FixedElems(:)
  !------------------------------------------------------------------------------

# 2662 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
     CALL Fatal('Get_ParMMG_Mesh',&
        'Remeshing utility ParMMG has not been installed')


END SUBROUTINE Get_ParMMG_Mesh

!A subroutine for a 3D mesh (in parallel) with ParMMG3D
!Inputs:
!   InMesh - the initial mesh
!   Metric - 2D real array specifying target metric
!   EdgePairs, PairCount - 202 edge elems so angle detection is not required
!   NodeFixed, ElemFixed - Optional mask to specify 'required' entities
!Output:
!   OutMesh - the improved mesh
!
SUBROUTINE DistributedRemeshParMMG(Model, InMesh,OutMesh,EdgePairs,PairCount,&
    NodeFixed,ElemFixed,Params,HVar,Angle)

  TYPE(Model_t) :: Model
  TYPE(Mesh_t), POINTER :: InMesh, OutMesh
  TYPE(ValueList_t), POINTER :: Params
  LOGICAL, ALLOCATABLE, OPTIONAL :: NodeFixed(:), ElemFixed(:)
  INTEGER, ALLOCATABLE, OPTIONAL :: EdgePairs(:,:)
  INTEGER, OPTIONAL :: PairCount  
  REAL(KIND=dp), OPTIONAL :: Angle
  TYPE(Variable_t), POINTER, OPTIONAL :: Hvar
  LOGICAL :: Success
  !-----------
  TYPE(Mesh_t), POINTER :: WorkMesh
  TYPE(ValueList_t), POINTER :: FuncParams, Material
  TYPE(Variable_t), POINTER :: TimeVar, MMGVar
  TYPE(Element_t), POINTER :: Element
  REAL(KIND=dp), ALLOCATABLE :: TargetLength(:,:), Metric(:,:),hminarray(:),hausdarray(:)
  REAL(KIND=dp), POINTER :: WorkReal(:,:,:) => NULL()
  REAL(KIND=dp) :: hsiz(3),hmin,hmax,hgrad,hausd,RemeshMinQuality,Quality, TargetX
  INTEGER :: i,j,MetricDim,NNodes,NBulk,NBdry,ierr,SolType,body_offset,&
       nBCs,NodeNum(1), MaxRemeshIter, mmgloops, ElemBodyID, &
       NVerts, NTetras, NPrisms, NTris, NQuads, NEdges, Counter, Time
  INTEGER, ALLOCATABLE :: TetraQuality(:)
  LOGICAL :: Debug, Parallel, AnisoFlag, Found, SaveMMGMeshes, SaveMMGSols, FreezeInternal
  LOGICAL, ALLOCATABLE :: RmElement(:)
  CHARACTER(:), ALLOCATABLE :: MeshName, SolName, &
        premmg_meshfile, mmg_meshfile, premmg_solfile, mmg_solfile
  CHARACTER(*), PARAMETER :: FuncName = "DistributedRemeshParMMG3D"
  SAVE :: WorkReal 

# 2997 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
  CALL Fatal(FuncName, "Remeshing utility PMMG has not been installed")


END SUBROUTINE DistributedRemeshParMMG


!------------------------------------------------------------------------------
! 2D remeshing routine copied from MMG2DSolver.F90 to library of Elmer.
! Here is the original author information:
! 
! ******************************************************************************
! *
! *  Author: F. Gillet-Chaulet (IGE)
! *  Email:  fabien.gillet-chaulet@univ-grenoble-alpes.fr
! *  Web:    http://elmerice.elmerfem.org
! *
! *  Original Date: 13-07-2017, 
! *****************************************************************************
!------------------------------------------------------------------------------
  FUNCTION GET_MMG2D_MESH(MeshNumber,OutputFilename) RESULT(NewMesh)
    IMPLICIT NONE
!------------------------------------------------------------------------------
    INTEGER :: MeshNumber
    TYPE(Mesh_t), POINTER :: NewMesh
    CHARACTER(LEN=MAX_NAME_LEN) :: OutPutFileName
!------------------------------------------------------------------------------
# 3382 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
  CALL Fatal('Get_MMG2D_Mesh', "Remeshing utility MMG has not been installed")

  
  END FUNCTION GET_MMG2D_MESH


  SUBROUTINE SET_MMG2D_SOL(Mesh,MeshSize,Scalar)
    IMPLICIT NONE
    TYPE(Mesh_t), POINTER :: Mesh
    TYPE(Variable_t), POINTER :: MeshSize
    LOGICAL :: Scalar
    REAL(KIND=dp) :: M11,M22,M12
    INTEGER :: NVert
    INTEGER :: ier
    INTEGER :: ii,jj
    LOGICAL :: Debug = .FALSE.
    CHARACTER(LEN=MAX_NAME_LEN) :: FuncName="Set_MMG2D_Sol"

# 3435 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
  CALL Fatal(FuncName,'Remeshing utility MMG has not been installed!')

        
  END SUBROUTINE Set_MMG2D_Sol


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  SUBROUTINE Set_MMG2D_Mesh(Mesh,Solver)
    IMPLICIT NONE
    TYPE(Mesh_t), POINTER :: Mesh
    TYPE(Solver_t), POINTER, OPTIONAL :: Solver
    
    CHARACTER(*), PARAMETER :: FuncName="Set_MMG2D_Mesh"
# 3594 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
    CALL Fatal(FuncName,'Remeshing utility MMG has not been installed')

    
  END SUBROUTINE SET_MMG2D_MESH


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  SUBROUTINE SET_MMG2D_Parameters(SolverParams)
    IMPLICIT NONE
    TYPE(ValueList_t), POINTER :: SolverParams
    CHARACTER(*), PARAMETER :: FuncName="Set_MMG2D_Parameters"
# 3740 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
    CALL Fatal(FuncName, "Remeshing utility MMG has not been installed")

        
  END SUBROUTINE Set_MMG2D_Parameters



  FUNCTION MMG2D_ReMesh( RefMesh, Hvar, Solver) RESULT ( NewMesh ) 

    TYPE(Mesh_t), POINTER :: NewMesh, RefMesh
    TYPE(Variable_t), POINTER, OPTIONAL :: Hvar
    TYPE(Solver_t), POINTER, OPTIONAL :: Solver 
    CHARACTER(*), PARAMETER :: FuncName="MMG2D_ReMesh"
# 3822 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/src/MeshRemeshing.F90"
    CALL Fatal(FuncName,'Remeshing utility MMG has not been installed!')

    
  END FUNCTION MMG2D_ReMesh



  SUBROUTINE Finalize_MMG_Mesh(Mesh)

     TYPE(Mesh_t), POINTER :: Mesh

     CHARACTER(:), ALLOCATABLE :: ElementDef, ElementDef0
     INTEGER ::  i,j,Def_DOFs(10,6)
     TYPE(Solver_t), POINTER :: Solver
     LOGICAL :: stat, GotMesh = .FALSE.


      Solver => CurrentModel % Solver


      Def_Dofs = -1; Def_Dofs(:,1)=1

      ! Define what kind of element we are working with in this solver
      !-----------------------------------------------------------------
      ElementDef = ListGetString( Solver % Values, 'Element', stat )

      IF ( .NOT. stat ) THEN
        IF ( ListGetLogical( Solver % Values, 'Discontinuous Galerkin', stat ) ) THEN
           Solver % Def_Dofs(:,:,4) = 0  ! The final value is set when calling LoadMesh2
           IF ( .NOT. GotMesh ) Def_Dofs(:,4) = MAX(Def_Dofs(:,4),0 )
           i=i+1
           Solver % DG = .TRUE.
!          CYCLE
        ELSE
           ElementDef = "n:1"
        END IF
      END IF

      ElementDef0 = ElementDef
      DO WHILE(.TRUE.)
        j = INDEX( ElementDef0, '-' )
        IF (j == 1) THEN
          ElementDef0 = ElementDef0(2:)
          j = INDEX( ElementDef0, '-' )
        END IF
        IF (j>0) THEN
          !
          ! Read the element definition up to the next flag which specifies the
          ! target element set
          !
          ElementDef = ElementDef0(1:j-1)
        ELSE
          ElementDef = ElementDef0
        END IF
        !  Calling GetDefs fills Def_Dofs arrays:
        CALL GetDefs( ElementDef, Solver % Def_Dofs, Def_Dofs(:,:), .NOT. GotMesh, &
            Solver % DG)
        IF(j>0) THEN
          ElementDef0 = ElementDef0(j+1:)
        ELSE
          EXIT
        END IF
      END DO

      CALL PrepareMesh( CurrentModel, Mesh, ParEnv % PEs>1 , Def_Dofs )

!CONTAINS



END SUBROUTINE Finalize_MMG_Mesh
    
  
END MODULE MeshRemeshing
