# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/mathlibs/src/arpack/icnteq.f"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/mathlibs/src/arpack/icnteq.f"
c
c-----------------------------------------------------------------------
c
c     Count the number of elements equal to a specified integer value.
c
      integer function icnteq (n, array, value)
c
      integer    n, value
      integer    array(*)
c
      k = 0
      do 10 i = 1, n
         if (array(i) .eq. value) k = k + 1
   10 continue
      icnteq = k
c
      return
      end
