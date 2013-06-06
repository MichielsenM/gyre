! Module   : gyre_sysmtx
! Purpose  : blocked system matrix
!
! Copyright 2013 Rich Townsend
!
! This file is part of GYRE. GYRE is free software: you can
! redistribute it and/or modify it under the terms of the GNU General
! Public License as published by the Free Software Foundation, version 3.
!
! GYRE is distributed in the hope that it will be useful, but WITHOUT
! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
! or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
! License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

$include 'core.inc'

module gyre_sysmtx

  ! Uses

  use core_kinds
  use core_parallel
  use core_linalg

  use gyre_ext_arith
  use gyre_linalg

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type sysmtx_t
     private
     complex(WP), allocatable         :: B_i(:,:)   ! Inner boundary conditions
     complex(WP), allocatable         :: B_o(:,:)   ! Outer boundary conditions
     complex(WP), allocatable         :: E_l(:,:,:) ! Left equation blocks
     complex(WP), allocatable         :: E_r(:,:,:) ! Right equation blocks
     type(ext_complex_t), allocatable :: S(:)       ! Block scales
     integer                          :: n          ! Number of equation blocks
     integer                          :: n_e        ! Number of equations per block
     integer                          :: n_i        ! Number of inner boundary conditions
     integer                          :: n_o        ! Number of outer boundary conditions
   contains
     private
     procedure, public :: init
     procedure, public :: set_inner_bound
     procedure, public :: set_outer_bound
     procedure, public :: set_block
     procedure, public :: determinant
     procedure, public :: determinant_slu_r
     procedure, public :: determinant_slu_c
     procedure, public :: null_vector => null_vector_banded
!     procedure, public :: null_vector => null_vector_inviter
  end type sysmtx_t

  ! Access specifiers

  private

  public :: sysmtx_t

  ! Procedures

contains

  subroutine init (this, n, n_e, n_i, n_o)

    class(sysmtx_t), intent(out) :: this
    integer, intent(in)          :: n
    integer, intent(in)          :: n_e
    integer, intent(in)          :: n_i
    integer, intent(in)          :: n_o

    ! Initialize the sysmtx

    allocate(this%E_l(n_e,n_e,n))
    allocate(this%E_r(n_e,n_e,n))

    allocate(this%B_i(n_i,n_e))
    allocate(this%B_o(n_o,n_e))

    allocate(this%S(n))

    this%n = n
    this%n_e = n_e
    this%n_i = n_i
    this%n_o = n_o

    ! Finish

    return

  end subroutine init

!****

  subroutine set_inner_bound (this, B_i)

    class(sysmtx_t), intent(inout)  :: this
    complex(WP), intent(in)         :: B_i(:,:)

    $CHECK_BOUNDS(SIZE(B_i, 1),this%n_i)
    $CHECK_BOUNDS(SIZE(B_i, 2),this%n_e)

    ! Set the inner boundary conditions

    this%B_i = B_i

    ! Finish

    return

  end subroutine set_inner_bound

!****

  subroutine set_outer_bound (this, B_o)

    class(sysmtx_t), intent(inout)  :: this
    complex(WP), intent(in)         :: B_o(:,:)

    $CHECK_BOUNDS(SIZE(B_o, 1),this%n_o)
    $CHECK_BOUNDS(SIZE(B_o, 2),this%n_e)

    ! Set the outer boundary conditions

    this%B_o = B_o

    ! Finish

    return

  end subroutine set_outer_bound

!****

  subroutine set_block (this, k, E_l, E_r, S)

    class(sysmtx_t), intent(inout)  :: this
    integer, intent(in)             :: k
    complex(WP), intent(in)         :: E_l(:,:)
    complex(WP), intent(in)         :: E_r(:,:)
    type(ext_complex_t), intent(in) :: S

    $CHECK_BOUNDS(SIZE(E_l, 1),this%n_e)
    $CHECK_BOUNDS(SIZE(E_l, 2),this%n_e)

    $CHECK_BOUNDS(SIZE(E_r, 1),this%n_e)
    $CHECK_BOUNDS(SIZE(E_r, 2),this%n_e)

    $ASSERT(k >= 1,Invalid block index)
    $ASSERT(k <= this%n,Invalid block index)

    ! Set the block

    this%E_l(:,:,k) = E_l
    this%E_r(:,:,k) = E_r

    this%S(k) = S

    ! Finish

    return

  end subroutine set_block

!****

  function determinant (this, use_real) result (det)

    class(sysmtx_t), intent(inout) :: this
    type(ext_complex_t)            :: det
    logical, intent(in), optional  :: use_real

    logical :: use_real_

    if(PRESENT(use_real)) then
       use_real_ = use_real
    else
       use_real_ = .FALSE.
    endif

    ! Calculate the sysmtx determinant

    if(use_real_) then
       det = ext_complex(this%determinant_slu_r())
    else
       det = this%determinant_slu_c()
    end if

    ! Finish
    
    return

  end function determinant

!****

  function determinant_slu_c (this) result (det)

    class(sysmtx_t), intent(inout) :: this
    type(ext_complex_t)            :: det

    integer             :: n
    integer             :: n_e
    integer             :: l
    integer             :: k
    complex(WP)         :: M_G(2*this%n_e,this%n_e)
    complex(WP)         :: M_U(2*this%n_e,this%n_e)
    complex(WP)         :: M_E(2*this%n_e,this%n_e)
    integer             :: ipiv(this%n_e)
    integer             :: info
    integer             :: i
    type(ext_complex_t) :: block_det(this%n)
    integer             :: n_i
    complex(WP)         :: M(2*this%n_e,2*this%n_e)
    integer             :: ipiv2(2*this%n_e)

    ! Calculate the determinant of the sysmtx using the structured
    ! factorization (SLU) algorithm by Wright (1994)

    det = ext_complex(1._WP)

    associate(A => this%E_l, C => this%E_r)

      ! Repeatedly halve the number of these blocks using SLU with a
      ! partition size of one or two

      n = this%n
      n_e = this%n_e

      l = 1

      factor_loop : do

         if (l >= n) exit factor_loop

         ! Reduce pairs of blocks to single blocks

         !$OMP PARALLEL DO SCHEDULE (DYNAMIC) PRIVATE (M_G, M_U, M_E, ipiv, info, i)
         reduce_loop : do k = 1, n-l, 2*l

            ! Set up matrices (see expressions following eqn. 2.5 of
            ! Wright 1994)

            M_G(:n_e,:) = A(:,:,k)
            M_G(n_e+1:,:) = 0._WP

            M_U(:n_e,:) = C(:,:,k)
            M_U(n_e+1:,:) = A(:,:,k+l)

            M_E(:n_e,:) = 0._WP
            M_E(n_e+1:,:) = C(:,:,k+l)

            ! Calculate the LU factorization of M_U, and use it to reduce
            ! M_E and M_G. The nasty fpx3 stuff is to ensure the correct
            ! LAPACK/BLAS routines are called (can't use generics, since
            ! we're then not allowed to pass array elements into
            ! assumed-size arrays; see, e.g., p. 268 of Metcalfe & Reid,
            ! "Fortran 90/95 Explained")

            call XGETRF(2*n_e, n_e, M_U, 2*n_e, ipiv, info)
            $ASSERT(info >= 0, Negative return from XGETRF)

            $block

            $if($DOUBLE_PRECISION)
            $local $X Z
            $else
            $local $X C
            $endif

            call ${X}LASWP(n_e, M_E, 2*n_e, 1, n_e, ipiv, 1)
            call ${X}TRSM('L', 'L', 'N', 'U', n_e, n_e, &
                 CMPLX(1._WP, KIND=WP), M_U(1,1), 2*n_e, M_E(1,1), 2*n_e)
            call ${X}GEMM('N', 'N', n_e, n_e, n_e, CMPLX(-1._WP, KIND=WP), &
                 M_U(n_e+1,1), 2*n_e, M_E(1,1), 2*n_e, CMPLX(1._WP, KIND=WP), &
                 M_E(n_e+1,1), 2*n_e)

            call ${X}LASWP(n_e, M_G, 2*n_e, 1, n_e, ipiv, 1)
            call ${X}TRSM('L', 'L', 'N', 'U', n_e, n_e, &
                 CMPLX(1._WP, KIND=WP), M_U(1,1), 2*n_e, M_G(1,1), 2*n_e)
            call ${X}GEMM('N', 'N', n_e, n_e, n_e, CMPLX(-1._WP, KIND=WP), &
                 M_U(n_e+1,1), 2*n_e, M_G(1,1), 2*n_e, CMPLX(1._WP, KIND=WP), &
                 M_G(n_e+1,1), 2*n_e)

            $endblock

            ! Calculate the block determinant

            block_det(k) = product(ext_complex(diagonal(M_U)))

            do i = 1,n_e
               if(ipiv(i) /= i) block_det(k) = -block_det(k)
            end do

            ! Store results

            C(:,:,k) = M_E(n_e+1:,:)
            A(:,:,k) = M_G(n_e+1:,:)

         end do reduce_loop

         ! Update the determinant

         det = product([block_det(:n-l:2*l),det])

         ! Loop around

         l = 2*l

      end do factor_loop

      ! Process the final matrix, consisting of the boundary conditions
      ! plus a single internal block

      n_i = this%n_i

      M(:n_i,:n_e) = this%B_i
      M(n_i+1:n_i+n_e,:n_e) = A(:,:,1)
      M(n_i+n_e+1:,:n_e) = 0._WP

      M(:n_i,n_e+1:) = 0._WP
      M(n_i+1:n_i+n_e,n_e+1:) = C(:,:,1)
      M(n_i+n_e+1:,n_e+1:) = this%B_o

      call XGETRF(2*n_e, 2*n_e, M, 2*n_e, ipiv2, info)
      $ASSERT(info >= 0, Negative return from XGETRF)

      det = product([ext_complex(diagonal(M)),det,this%S])

      do i = 1,2*n_e
         if(ipiv2(i) /= i) det = -det
      end do

    end associate

    ! Finish

    return

  end function determinant_slu_c

!****

  function determinant_slu_r (this) result (det)

    class(sysmtx_t), intent(inout) :: this
    type(ext_real_t)               :: det

    integer          :: n
    integer          :: n_e
    integer          :: l
    integer          :: k
    real(WP)         :: M_G(2*this%n_e,this%n_e)
    real(WP)         :: M_U(2*this%n_e,this%n_e)
    real(WP)         :: M_E(2*this%n_e,this%n_e)
    integer          :: ipiv(this%n_e)
    integer          :: info
    integer          :: i
    type(ext_real_t) :: block_det(this%n)
    integer          :: n_i
    real(WP)         :: M(2*this%n_e,2*this%n_e)
    integer          :: ipiv2(2*this%n_e)

    ! Calculate the determinant of the sysmtx using the structured
    ! factorization (SLU) algorithm by Wright (1994), assuming that
    ! the imaginary parts can be discarded

    det = ext_real(1._WP)

    associate(A => this%E_l, C => this%E_r)

      ! Repeatedly halve the number of these blocks using SLU with a
      ! partition size of one or two

      n = this%n
      n_e = this%n_e

      l = 1

      factor_loop : do
       
         if (l >= n) exit factor_loop

         ! Reduce pairs of blocks to single blocks

         !$OMP PARALLEL DO SCHEDULE (DYNAMIC) PRIVATE (M_G, M_U, M_E, ipiv, info, i)
         reduce_loop : do k = 1, n-l, 2*l

            ! Set up matrices (see expressions following eqn. 2.5 of
            ! Wright 1994)

            M_G(:n_e,:) = REAL(A(:,:,k))
            M_G(n_e+1:,:) = 0._WP

            M_U(:n_e,:) = REAL(C(:,:,k))
            M_U(n_e+1:,:) = REAL(A(:,:,k+l))

            M_E(:n_e,:) = 0._WP
            M_E(n_e+1:,:) = REAL(C(:,:,k+l))
            
            ! Calculate the LU factorization of M_U, and use it to reduce
            ! M_E and M_G. The nasty fpx3 stuff is to ensure the correct
            ! LAPACK/BLAS routines are called (can't use generics, since
            ! we're then not allowed to pass array elements into
            ! assumed-size arrays; see, e.g., p. 268 of Metcalfe & Reid,
            ! "Fortran 90/95 Explained")

            call XGETRF(2*n_e, n_e, M_U, 2*n_e, ipiv, info)
            $ASSERT(info >= 0, Negative return from XGETRF)

            $block

            $if($DOUBLE_PRECISION)
            $local $X D
            $else
            $local $X S
            $endif

            call ${X}LASWP(n_e, M_G, 2*n_e, 1, n_e, ipiv, 1)
            call ${X}TRSM('L', 'L', 'N', 'U', n_e, n_e, &
                 1._WP, M_U(1,1), 2*n_e, M_G(1,1), 2*n_e)
            call ${X}GEMM('N', 'N', n_e, n_e, n_e, -1._WP, &
                 M_U(n_e+1,1), 2*n_e, M_G(1,1), 2*n_e, 1._WP, &
                 M_G(n_e+1,1), 2*n_e)

            call ${X}LASWP(n_e, M_E, 2*n_e, 1, n_e, ipiv, 1)
            call ${X}TRSM('L', 'L', 'N', 'U', n_e, n_e, &
                 1._WP, M_U(1,1), 2*n_e, M_E(1,1), 2*n_e)
            call ${X}GEMM('N', 'N', n_e, n_e, n_e, -1._WP, &
                 M_U(n_e+1,1), 2*n_e, M_E(1,1), 2*n_e, 1._WP, &
                 M_E(n_e+1,1), 2*n_e)

            $endblock

            ! Calculate the block determinant

            block_det(k) = product(ext_real(diagonal(M_U)))

            do i = 1,n_e
               if(ipiv(i) /= i) block_det(k) = -block_det(k)
            end do

            ! Store results

            A(:,:,k) = M_G(n_e+1:,:)
            C(:,:,k) = M_E(n_e+1:,:)

         end do reduce_loop

         ! Update the determinant

         det = product([block_det(:n-l:2*l),det])

         ! Loop around

         l = 2*l

      end do factor_loop

      ! Process the final matrix, consisting of the boundary conditions
      ! plus a single internal block

      n_i = this%n_i

      M(:n_i,:n_e) = REAL(this%B_i)
      M(n_i+1:n_i+n_e,:n_e) = REAL(A(:,:,1))
      M(n_i+n_e+1:,:n_e) = 0._WP

      M(:n_i,n_e+1:) = 0._WP
      M(n_i+1:n_i+n_e,n_e+1:) = REAL(C(:,:,1))
      M(n_i+n_e+1:,n_e+1:) = REAL(this%B_o)

      call XGETRF(2*n_e, 2*n_e, M, 2*n_e, ipiv2, info)
      $ASSERT(info >= 0, Negative return from XGETRF)

      det = product([ext_real(diagonal(M)),det,ext_real(this%S)])

      do i = 1,2*n_e
         if(ipiv2(i) /= i) det = -det
      end do

    end associate

    ! Finish

    return

  end function determinant_slu_r

!****

  subroutine pack_banded (sm, A_b)

    class(sysmtx_t), intent(in)           :: sm
    complex(WP), allocatable, intent(out) :: A_b(:,:)

    integer :: n_l
    integer :: n_u
    integer :: k
    integer :: i_b
    integer :: j_b
    integer :: i
    integer :: j

    ! Pack the sysmtx into LAPACK's banded-matrix sparse format

    n_l = sm%n_e + sm%n_i - 1
    n_u = sm%n_e + sm%n_i - 1

    allocate(A_b(2*n_l+n_u+1,sm%n_e*(sm%n+1)))

    ! Inner boundary conditions
    
    A_b = 0._WP

    do j_b = 1, sm%n_e
       j = j_b
       do i_b = 1, sm%n_i
          i = i_b
          A_b(n_l+n_u+1+i-j,j) = sm%B_i(i_b,j_b)
       end do
    end do

    ! Left equation blocks

    do k = 1, sm%n
       do j_b = 1, sm%n_e
          j = (k-1)*sm%n_e + j_b
          do i_b = 1, sm%n_e
             i = (k-1)*sm%n_e + i_b + sm%n_i
             A_b(n_l+n_u+1+i-j,j) = sm%E_l(i_b,j_b,k)
          end do
       end do
    end do

    ! Right equation blocks

    do k = 1, sm%n
       do j_b = 1, sm%n_e
          j = k*sm%n_e + j_b
          do i_b = 1, sm%n_e
             i = (k-1)*sm%n_e + sm%n_i + i_b
             A_b(n_l+n_u+1+i-j,j) = sm%E_r(i_b,j_b,k)
          end do
       end do
    end do

    ! Outer boundary conditions

    do j_b = 1, sm%n_e
       j = sm%n*sm%n_e + j_b
       do i_b = 1, sm%n_o
          i = sm%n*sm%n_e + sm%n_i + i_b
          A_b(n_l+n_u+1+i-j,j) = sm%B_o(i_b,j_b)
       end do
    end do

    ! Finish

    return

  end subroutine pack_banded

!****

  function null_vector_banded (this) result(b)

    class(sysmtx_t), intent(in) :: this
    complex(WP)                 :: b(this%n_e*(this%n+1))

    complex(WP), allocatable :: A_b(:,:)
    integer                  :: n_l
    integer                  :: n_u
    integer, allocatable     :: ipiv(:)
    integer                  :: info
    integer                  :: i
    complex(WP), allocatable :: A_r(:,:)
    complex(WP), allocatable :: Mb(:,:)
    integer                  :: j
    integer                  :: n_lu
    
    ! Pack the smatrix into banded form

    call pack_banded(this, A_b)

    ! LU decompose it

    n_l = this%n_e + this%n_i - 1
    n_u = this%n_e + this%n_i - 1

    allocate(ipiv(SIZE(A_b, 2)))

    call XGBTRF(SIZE(A_b, 2), SIZE(A_b, 2), n_l, n_u, A_b, SIZE(A_b, 1), ipiv, info)
    $ASSERT(info == 0 .OR. info == SIZE(A_b,2),Non-zero return from LA_GBTRF)

    ! Locate the smallest diagonal element

    i = MINLOC(ABS(A_b(n_l+n_u+1,:)), DIM=1)

    if(SIZE(A_b, 2)-i > this%n_e) then
       $WARN(Smallest element not in final block)
    endif

    ! Backsubstitute to solve the banded linear system A_b b = 0

    allocate(A_r(2*n_l+n_u+1,i-1))
    allocate(Mb(i-1,1))

    deallocate(ipiv)
    allocate(ipiv(i-1))

    if(i > 1) then 

       ! Set up the reduced LU system

       A_r(:n_l+n_u+1,:) = A_b(:n_l+n_u+1,:i-1)
       A_r(n_l+n_u+2:,:) = 0._WP

       ! The following line seems to cause out-of-memory errors when
       ! compiled with gfortran 4.8.0 on MVAPICH systems. Very puzzling!
       !
       ! ipiv = [(j,j=1,i-1)]

       do j = 1,i-1
          ipiv(j) = j
       enddo

       ! Solve for the 1:i-1 components of b

       n_lu = MIN(n_l+n_u, i-1)

       Mb(:i-n_lu-1,1) = 0._WP
       Mb(i-n_lu:,1) = -A_b(n_l+n_u+1-n_lu:n_l+n_u,i)

       call XGBTRS('N', SIZE(A_r, 2), n_l, n_u, 1, A_r, SIZE(A_r, 1), ipiv, Mb, SIZE(Mb, 1), info)
       $ASSERT(info == 0,Non-zero return from XGBTRS)

       b(:i-1) = Mb(:,1)

    end if
       
    ! Fill in the other parts of b
    
    b(i) = 1._WP
    b(i+1:) = 0._WP

    ! Finish

    return

  end function null_vector_banded

!****

  function null_vector_inviter (this) result(b)

    class(sysmtx_t), intent(in) :: this
    complex(WP)                 :: b(this%n_e*(this%n+1))

    integer, parameter  :: MAX_ITER = 25
    real(WP), parameter :: EPS = 4._WP*EPSILON(0._WP)

    complex(WP), allocatable :: A_b(:,:)
    integer, allocatable     :: ipiv(:)
    integer                  :: n_l
    integer                  :: n_u
    integer                  :: info
    integer                  :: i
    complex(WP)              :: y(this%n_e*(this%n+1),1)
    complex(WP)              :: v(this%n_e*(this%n+1),1)
    complex(WP)              :: w(this%n_e*(this%n+1))
    complex(WP)              :: theta
!    integer                  :: j

    ! **** NOTE: THIS ROUTINE IS CURRENTLY OUT-OF-ACTION; IT GIVES
    ! **** MUCH POORER RESULTS THAN null_vector_banded, AND IT'S NOT
    ! **** CLEAR WHY

    ! Pack the sysmtx into banded form

    call pack_banded(this, A_b)

    ! LU decompose it

    n_l = this%n_e + this%n_i - 1
    n_u = this%n_e + this%n_i - 1

    allocate(ipiv(SIZE(A_b, 2)))

    call XGBTRF(SIZE(A_b, 2), SIZE(A_b, 2), n_l, n_u, A_b, SIZE(A_b, 1), ipiv, info)
    $ASSERT(info == 0 .OR. info == SIZE(A_b,2),Non-zero return from LA_GBTRF)

    ! Locate the smallest diagonal element

    i = MINLOC(ABS(A_b(n_l+n_u+1,:)), DIM=1)

    if(SIZE(A_b, 2)-i > this%n_e) then
       $WARN(Smallest element not in final block)
    endif

    ! Use inverse iteration to converge on the null vector

!    tol = EPS*SQRT(REAL(SIZE(x), WP))

    y = 1._WP/SQRT(REAL(SIZE(b), WP))

    iter_loop : do i = 1,MAX_ITER

       v(:,1) = y(:,1)/SQRT(DOT_PRODUCT(y(:,1), y(:,1)))

       y = v
       call XGBTRS('N', SIZE(A_b, 2), n_l, n_u, 1, A_b, SIZE(A_b, 1), ipiv, y, SIZE(y, 1), info)
       $ASSERT(info == 0,Non-zero return from XGBTRS)

       theta = DOT_PRODUCT(v(:,1), y(:,1))

       w = y(:,1) - theta*v(:,1)

       if(ABS(SQRT(DOT_PRODUCT(w, w))) < 4.*EPSILON(0._WP)*ABS(theta)) exit iter_loop

    end do iter_loop

    b = y(:,1)/theta

    ! Finish

    ! return

  end function null_vector_inviter

end module gyre_sysmtx
