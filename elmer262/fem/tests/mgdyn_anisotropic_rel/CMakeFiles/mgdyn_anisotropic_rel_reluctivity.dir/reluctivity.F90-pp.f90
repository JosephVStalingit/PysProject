# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/mgdyn_anisotropic_rel/reluctivity.F90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/fem/tests/mgdyn_anisotropic_rel/reluctivity.F90"
!-------------------------------------------------------------------------------
SUBROUTINE reluct(Model, n, X, Y)
!-------------------------------------------------------------------------------
  USE DefUtils
  IMPLICIT NONE
  TYPE(Model_t) :: Model
  INTEGER :: n
  REAL(KIND=dp) :: X(*)
  REAL(KIND=dp), POINTER  :: Y(:,:)
!-------------------------------------------------------------------------------
  
  Y = 0._dp
  Y(1,1) = 0.001_dp
  Y(2,2) = 1/(sqrt(x(1)**2 + x(3)**2)*1e3 + 1e5)
  Y(3,3) = 0.001_dp
!-------------------------------------------------------------------------------
END SUBROUTINE reluct
!-------------------------------------------------------------------------------
