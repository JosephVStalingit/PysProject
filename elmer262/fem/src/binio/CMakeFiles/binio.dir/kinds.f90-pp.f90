# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build/fem/src/binio/kinds.f90"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "C:/Users/JosephVStalin/Desktop/PysProject/elmerfem-release-26.2.1/build/fem/src/binio/kinds.f90"
MODULE Kinds

    ! IntOff_k is the kind of the file offsets used by ftello and fseeko,
    ! corresponds to a C off_t.
    INTEGER, PARAMETER :: IntOff_k = selected_int_kind(18)

    INTEGER, PARAMETER :: Int4_k = selected_int_kind(9)
    INTEGER, PARAMETER :: Int8_k = selected_int_kind(18)

END MODULE Kinds
