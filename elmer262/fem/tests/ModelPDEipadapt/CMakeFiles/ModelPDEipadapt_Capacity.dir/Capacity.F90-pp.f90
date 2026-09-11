# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/ModelPDEipadapt/Capacity.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/ModelPDEipadapt/Capacity.F90"

  FUNCTION Capacity( Model, n, t ) RESULT(f)
    USE DefUtils
    IMPLICIT NONE
    
    TYPE(Model_t) :: Model
    INTEGER :: n
    REAL(KIND=dp) :: t,f

    REAL(KIND=dp) :: x
    REAL(KIND=dp) :: Width
    LOGICAL :: Visited = .FALSE.

    SAVE Width, Visited 
    
    IF(.NOT. Visited ) THEN
      Width = ListGetConstReal( Model % Simulation,'Bandwidth Parameter' )
      PRINT *,'Bandwidth Parameter:',Width 
      Visited = .TRUE.
    END IF
    
    x = ABS( t / Width )

    IF( x > 1.0_dp ) THEN
      f = 1.0_dp
    ELSE
      f = 1.0_dp + 0.5 *(1+COS(PI*x)) / Width
    END IF

  END FUNCTION Capacity
