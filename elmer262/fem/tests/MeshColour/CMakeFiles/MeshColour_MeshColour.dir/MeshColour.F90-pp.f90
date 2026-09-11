# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/MeshColour/MeshColour.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/MeshColour/MeshColour.F90"
SUBROUTINE MeshColour_init( Model,Solver,dt,TransientSimulation )
    USE DefUtils
    IMPLICIT NONE
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model
    TYPE(Solver_t) :: Solver
    REAL(KIND=dp) :: dt
    LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
    TYPE(ValueList_t), POINTER :: Params
    INTEGER :: NormInd
    LOGICAL :: Found

    Params => GetSolverParams()

    NormInd = ListGetInteger( Params,'Norm Variable Index',Found)
    IF( NormInd > 0 ) THEN
      IF( .NOT. ListCheckPresent( Params,'Variable') ) THEN
        CALL ListAddString( Solver % Values,'Variable',&
                '-nooutput -global meshcolour_var')
      END IF
    END IF
    
END SUBROUTINE MeshColour_init

SUBROUTINE MeshColour( Model,Solver,dt,TransientSimulation )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Test multithreaded mesh colouring routines in Elmer
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear & nonlinear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
    USE DefUtils
    USE MeshUtils, ONLY : ElmerGraphColour, ElmerMeshToDualGraph, &
        ElmerColouringToGraph, Colouring_deallocate
    USE ISO_C_BINDING
    !------------------------------------------------------------------------------
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

    TYPE(Graph_t) :: DualGraph 
    TYPE(GraphColour_t) :: GraphColouring
    TYPE(Graph_t) :: ColourIndexList




    REAL(kind=dp) :: t_start, t_end

    INTEGER :: nerror, nerror_metis, nerror_colour, nerror_clist

    nerror = 0
    Mesh => GetMesh()

    ! Create dual mesh
    t_start = ftimer()
    CALL ElmerMeshToDualGraph(Mesh, DualGraph)
    t_end = ftimer()
    WRITE (*,'(A,ES12.3,A)') 'Dual graph creation total: ', t_end - t_start, ' sec.'

    ! Verify dual mesh with Metis (for completeness, 
    ! not compiled in by default)
# 97 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/MeshColour/MeshColour.F90"

    ! Colour mesh
    t_start = ftimer()
    CALL ElmerGraphColour(DualGraph, GraphColouring)
    t_end = ftimer()
    WRITE (*,'(A,ES12.3,A)') 'Graph colouring total: ', t_end - t_start, ' sec.'
    WRITE (*,'(A,I0)') 'Number of colours created ngc=', GraphColouring % nc
    CALL GraphColourVerify(DualGraph % n, DualGraph % ptr, & 
            DualGraph % ind, GraphColouring % nc, GraphColouring % colours, &
            nerror_colour)
    nerror = nerror + nerror_colour
    CALL Graph_Deallocate(DualGraph)

    t_start = ftimer()
    CALL ElmerColouringToGraph(GraphColouring, ColourIndexList)
    t_end = ftimer()
    WRITE (*,'(A,ES12.3,A)') 'Colour gather total: ', t_end-t_start, ' sec.'
    CALL GraphColourListVerify(GraphColouring % nc, GraphColouring % colours, &
            ColourIndexList % ptr, ColourIndexList % ind, nerror_clist)
    nerror = nerror + nerror_clist
    CALL Colouring_Deallocate(GraphColouring)
    CALL Graph_Deallocate(ColourIndexList)

    ! Build solution norm for error checking
    Solver % Variable % Norm = REAL(1+nerror,dp)
    Solver % Variable % Values = REAL(1+nerror,dp)
    
CONTAINS

  ! Portable wall-clock timer
  FUNCTION ftimer() RESULT(timerval)
    IMPLICIT NONE
    
    REAL(KIND=dp) :: timerval
    INTEGER(KIND=8) :: t, rate
    



    CALL SYSTEM_CLOCK(t,count_rate=rate)
    timerval = REAL(t,dp)/rate

  END FUNCTION ftimer

# 280 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/MeshColour/MeshColour.F90"

    SUBROUTINE GraphColourVerify(gn, gptr, gind, ngc, gc, err)
        IMPLICIT NONE

        INTEGER, INTENT(IN) :: gn
        INTEGER, INTENT(IN) :: gptr(:), gind(:)
        INTEGER, INTENT(IN) :: ngc
        INTEGER, INTENT(IN) :: gc(:)
        INTEGER :: err

        INTEGER :: c, v, w, vli, vti, vcol, wind, wcol
        REAL(KIND=dp) :: avg, dev
        INTEGER :: ccount(ngc)
        LOGICAL :: colourOk

        err = 0
        ccount = 0
        colourOk = .TRUE.
        ! Verify and count colours (in serial!)
        DO v=1,gn
            vli = gptr(v)
            vti = gptr(v+1)-1
            ! Get colour of v
            vcol = gc(v)

            ! Verify that colour is in range
            IF (vcol<1 .OR. vcol>ngc) THEN
                WRITE (*,'(A,I0,A,I0,A)') 'ERROR: Graph vertex v=', v, &
                        ' colour ', vcol, ' out of range' 
                colourOk = .FALSE.
                err = err + 1
                CYCLE
            ELSE
                ccount(vcol)=ccount(vcol)+1
            END IF

            ! Check colour versus each neighbour
            DO wind=vli,vti
                w = gind(wind)
                wcol = gc(w)
                IF (wcol == vcol) THEN
                    WRITE (*,'(A,I0,A,I0,A,I0)') 'ERROR: Neighbouring vertices (v,w)=(', v,',', w, &
                            ') of the same colour col=', vcol
                    colourOk = .FALSE.
                    err = err + 1
                END IF
            END DO
        END DO

        ! Compute average
        avg = REAL(SUM(ccount),dp)/ngc

        WRITE (*,'(A,I0,/,A,I0,/,A,ES12.3)') 'Number of vertices, n=', gn, &
                'Number of coloured vertices, nc=', SUM(ccount), &
                'Average vertices per colour avg=', avg
        ! Print out statistics
        DO c=1,ngc
            dev = ABS(avg-ccount(c))
            WRITE (*,'(A,I0,A,I0,A,ES12.3)') 'Colour c=', c, ', count=', ccount(c), ', average dev=', dev
        END DO
        IF (colourOk) THEN
            WRITE (*,'(A)') 'Colouring seems ok.'
        ELSE
            WRITE (*,'(A)') 'ERROR: Colouring seems inconsistent!'
        END IF
    END SUBROUTINE GraphColourVerify

    SUBROUTINE GraphColourListVerify(ngc, gc, cptr, cind, err)
        IMPLICIT NONE
        INTEGER, INTENT(IN) :: ngc
        INTEGER, INTENT(IN) :: gc(:)
        INTEGER, INTENT(IN) :: cptr(:), cind(:)
        INTEGER :: err

        INTEGER :: ccount(ngc)
        INTEGER, ALLOCATABLE :: cverify(:)
        INTEGER :: i, j, cli, cti,  n, ncol, totcol
        LOGICAL :: listsOk

        err = 0
        listsOk = .TRUE.

        n=size(gc)
        ! Count colours
        ccount = 0
        DO i=1,n
            ccount(gc(i))=ccount(gc(i))+1
        END DO

        ! Verify list pointers
        IF (SIZE(cptr) /= ngc+1 .OR. SIZE(cind) /= n) THEN
            WRITE (*,*) 'ERROR: Colour list pointer size does not', &
                    ' match the number of colours'
            err = err + 1
            RETURN
        END IF
        totcol = 0
        DO i=1,ngc
            ncol = cptr(i+1)-cptr(i)
            IF (ncol /= ccount(i)) THEN
                WRITE (*,'(3(A,I0))') 'ERROR: Colour=', i, ': pointer=', ncol,', count=', ccount(i)
                listsOk = .FALSE.
                err = err + 1
            END IF
        END DO
        ! Further verification of no use since pointers to lists are incorrect
        IF (.NOT. listsOk) RETURN

        IF (SUM(ccount) /= n) THEN
            WRITE (*,*) 'ERROR: Not enough colours in lists to cover the graph'
            listsOk = .FALSE.
        END IF

        ! Verify colours themselves
        ALLOCATE(cverify(n))

        cverify=0
        DO i=1,ngc
            cli = cptr(i)
            cti = cptr(i+1)-1
            DO j=cli,cti
                cverify(cind(j))=cverify(cind(j))+1
            END DO
        END DO
        DO i=1,n
            IF (cverify(i) > 1 .OR. cverify(i) < 1) THEN
                WRITE (*,'(2(A,I0))') 'ERROR: Vertex=', i, ', colour count=', cverify(i)
                listsOk = .FALSE.
                err = err + 1
            END IF
        END DO

        DEALLOCATE(cverify)

        IF (listsOk) THEN
            WRITE (*,'(A)') 'Colour lists seem ok.'
        ELSE
            WRITE (*,'(A)') 'ERROR: Colour lists seem inconsistent!'
        END IF
    END SUBROUTINE GraphColourListVerify

!------------------------------------------------------------------------------
END SUBROUTINE MeshColour
!------------------------------------------------------------------------------
