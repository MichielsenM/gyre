! Module   : gyre_parfait_model
! Purpose  : stellar parf (piecewise analytic representation) model
!
! Copyright 2022 Rich Townsend & The GYRE Team
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

module gyre_parfait_model

  ! Uses

  use core_kinds, only: WP

  use gyre_constants
  use gyre_grid
  use gyre_math
  use gyre_model
  use gyre_model_par
  use gyre_point
  use gyre_util

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type, extends (model_t) :: parfait_model_t
     private
     type(grid_t)          :: gr
     real(WP), allocatable :: x(:)
     real(WP), allocatable :: y(:)
     real(WP), allocatable :: z(:)
     real(WP), allocatable :: a(:)
     real(WP), allocatable :: d(:)
     real(WP), allocatable :: Gamma_1(:)
     real(WP)              :: Omega_rot
     real(WP)              :: beta_m
     real(WP)              :: beta_p
     logical               :: force_linear
     integer               :: s_i
     integer               :: s_o
   contains
     private
     procedure, public :: coeff
     procedure         :: coeff_V_2_
     procedure         :: coeff_As_
     procedure         :: coeff_U_
     procedure         :: coeff_c_1_
     procedure         :: coeff_Gamma_1_
     procedure, public :: dcoeff
     procedure         :: dcoeff_V_2_
     procedure         :: dcoeff_As_
     procedure         :: dcoeff_U_
     procedure         :: dcoeff_c_1_
     procedure, public :: is_defined
     procedure, public :: is_vacuum
     procedure, public :: Delta_p
     procedure, public :: Delta_g
     procedure, public :: grid
  end type parfait_model_t

  ! Interfaces

  interface parfait_model_t
     module procedure parfait_model_t_
  end interface parfait_model_t

  ! Access specifiers

  private

  public :: parfait_model_t

  ! Procedures

contains

  function parfait_model_t_ (x, d, Gamma_1, y_c, z_s, ml_p) result (ml)

    real(WP), intent(in)          :: x(:)
    real(WP), intent(in)          :: d(:)
    real(WP), intent(in)          :: Gamma_1(:)
    real(WP), intent(in)          :: y_c
    real(WP), intent(in)          :: z_s
    type(model_par_t), intent(in) :: ml_p
    type(parfait_model_t)         :: ml

    integer               :: n
    real(WP), allocatable :: y(:)
    real(WP), allocatable :: z(:)
    real(WP), allocatable :: a(:)
    integer               :: k
    real(WP)              :: b
    real(WP), allocatable :: gr_x(:)

    $CHECK_BOUNDS(SIZE(d), SIZE(x)-1)
    $CHECK_BOUNDS(SIZE(Gamma_1), SIZE(x)-1)

    ! Construct the parfait_model_t

    if (check_log_level('INFO')) then
       write(OUTPUT_UNIT, 100) 'Constructing parfait model'
100    format(A)
    endif

    ! Sanity checks

    n = SIZE(x)

    $ASSERT(ALL(x(2:n) > x(:n-1)),Non-monotonic radius coordinate)

    ! Integrate the dimensionless mass equation outward. Here, x=r/R,
    ! y=m/M, and d=rho*(R**3/M)

    allocate(y(n))

    y(1) = y_c

    y_loop: do k = 1, n-1
       y(k+1) = y(k) + 4._WP*PI*(x(k+1)**3 - x(k)**3)*d(k)/3._WP
    end do y_loop

    ! Integrate the dimensionless hydrostatic equilibrium equation
    ! inward. Here, z=P/(G*M**2/R**4)

    allocate(z(n))
    allocate(a(n-1))

    z(n) = z_s

    z_loop: do k = n-1, 1, -1

       a(k) = 2._WP*PI*(x(k+1)**2 - x(k)**2)*d(k)**2/3._WP

       if (x(k) > 0._WP) then
          b = (x(k)**(-1) - x(k+1)**(-1))*(x(k+1)**3*y(k) - x(k)**3*y(k+1))/(x(k+1)**3 - x(k)**3)*d(k)
       else
          b = 0._WP
       end if
       
       z(k) = z(k+1) + a(k) + b

    end do z_loop

    ! Store data

    ml%x = x
    ml%y = y
    ml%z = z
    ml%a = a
    ml%d = d

    ml%Gamma_1 = Gamma_1

    ml%Omega_rot = 0._WP

    ml%beta_m = ml_p%beta_m
    ml%beta_p = ml_p%beta_p

    ml%force_linear = ml_p%force_linear

    ! Set up the grid

    allocate(gr_x(2*n-2))

    gr_x(1) = x(1)
    gr_x(2:2*n-4:2) = x(2:n-1)
    gr_x(3:2*n-3:2) = x(2:n-1)
    gr_x(2*n-2) = x(n)

    ml%gr = grid_t(gr_x)

    ! Other stuff

    ml%s_i = ml%gr%s_i()
    ml%s_o = ml%gr%s_o()

    if (check_log_level('INFO')) then
       write(OUTPUT_UNIT, 110) 'Created', n, 'points'
110    format(3X,A,1X,I0,1X,A)
    endif

    ! Finish

    return

  end function parfait_model_t_

  !****

  function coeff (this, i, pt)

    class(parfait_model_t), intent(in) :: this
    integer, intent(in)                :: i
    type(point_t), intent(in)          :: pt
    real(WP)                           :: coeff

    $ASSERT_DEBUG(i >= 1 .AND. i <= I_LAST,Invalid index)
    $ASSERT_DEBUG(this%is_defined(i),Undefined coefficient)

    $ASSERT_DEBUG(pt%s >= this%s_i .AND. pt%s <= this%s_o,Invalid segment)

    ! Evaluate the i'th coefficient

    select case (i)
    case (I_V_2)
       coeff = this%coeff_V_2_(pt)
    case (I_AS)
       coeff = this%coeff_As_(pt)
    case (I_U)
       coeff = this%coeff_U_(pt)
    case (I_C_1)
       coeff = this%coeff_c_1_(pt)
    case (I_GAMMA_1)
       coeff = this%coeff_Gamma_1_(pt)
    case (I_OMEGA_ROT)
       coeff = this%Omega_rot
    end select

    ! Finish

    return

  end function coeff

  !****

  function coeff_V_2_ (this, pt) result (coeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: coeff

    real(WP) :: w_m1
    real(WP) :: w_1
    real(WP) :: w_2
    real(WP) :: z

    $ASSERT_DEBUG(.NOT. this%is_vacuum(pt),V_2 evaluation at vacuum point)

    ! Evaluate the V_2 coefficient

    associate (k => pt%s)

      ! Set up weight functions

      if (k > 1) then

         w_m1 = (pt%x**(-1) - this%x(k)**(-1))/(this%x(k+1)**(-1) - this%x(k)**(-1))

      else

         if (pt%x > 0._WP) then
            w_m1 = 1._WP
         else
            w_m1 = 0._WP
         endif

      endif
         
      w_1 = (pt%x - this%x(k))/(this%x(k+1) - this%x(k))
      w_2 = (pt%x**2 - this%x(k)**2)/(this%x(k+1)**2 - this%x(k)**2)

      ! Evaluate the dimensionless pressure

      if (this%force_linear) then
         z = (1._WP - w_1)*this%z(k) + w_1*this%z(k+1)
      else
         z = (1._WP - w_m1)*this%z(k) + w_m1*this%z(k+1) + (w_m1 - w_2)*this%a(k)
      end if

      ! Scale the value using beta_p

      z = (this%beta_p + (1._WP - this%beta_p)*pt%x)*z

      ! Evaluate the coefficient

      coeff = this%d(k)/(this%coeff_c_1_(pt)*z)

    end associate

    ! Finish

    return

  end function coeff_V_2_

  !****

  function coeff_As_ (this, pt) result (coeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: coeff

    $ASSERT_DEBUG(.NOT. this%is_vacuum(pt),As evaluation at vacuum point)

    ! Evaluate the As coefficient

    coeff = -this%coeff_V_2_(pt)*pt%x**2/this%coeff_Gamma_1_(pt)

    ! Finish

    return

  end function coeff_As_

  !****

  function coeff_U_ (this, pt) result (coeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: coeff

    ! Evaluate the U coefficient

    associate (k => pt%s)

      coeff = 4._WP*PI*this%coeff_c_1_(pt)*this%d(k)

    end associate

    ! Finish

    return

  end function coeff_U_

  !****

  function coeff_c_1_ (this, pt) result (coeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: coeff

    real(WP) :: w_1
    real(WP) :: w_3
    real(WP) :: m

    ! Evaluate the c_1 coefficient

    associate (k => pt%s)

      if (this%x(k) > 0._WP) then

         ! Set up weight functions

         w_1 = (pt%x - this%x(k))/(this%x(k+1) - this%x(k))
         w_3 = (pt%x**3 - this%x(k)**3)/(this%x(k+1)**3 - this%x(k)**3)

         ! Evaluate the dimensionless mass

         if (this%force_linear) then
            m = (1._WP - w_1)*this%y(k) + w_1*this%y(k+1)
         else
            m = (1._WP - w_3)*this%y(k) + w_3*this%y(k+1)
         end if

         ! Scale the values using beta_m

         m = (this%beta_m + (1._WP - this%beta_m)*pt%x)*m

         ! Evaluate the coefficient

         coeff = pt%x**3/m

      else

         coeff = 3._WP/(4._WP*PI*this%d(1))

      end if

    end associate

    ! Finish

    return

  end function coeff_c_1_

  !****

  function coeff_Gamma_1_ (this, pt) result (coeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: coeff

    ! Evaluate the Gamma_1 coefficient

    associate (k => pt%s)

      coeff = this%Gamma_1(k)

    end associate
    ! Finish

    return

  end function coeff_Gamma_1_

  !****

  function dcoeff (this, i, pt)

    class(parfait_model_t), intent(in) :: this
    integer, intent(in)                :: i
    type(point_t), intent(in)          :: pt
    real(WP)                           :: dcoeff

    $ASSERT_DEBUG(i >= 1 .AND. i <= I_LAST,Invalid index)
    $ASSERT_DEBUG(this%is_defined(i),Undefined coefficient)

    $ASSERT_DEBUG(pt%s >= this%s_i .AND. pt%s <= this%s_o,Invalid segment)

    ! Evaluate the i'th coefficient

    select case (i)
    case (I_V_2)
       dcoeff = this%dcoeff_V_2_(pt)
    case (I_AS)
       dcoeff = this%dcoeff_As_(pt)
    case (I_U)
       dcoeff = this%dcoeff_U_(pt)
    case (I_C_1)
       dcoeff = this%dcoeff_c_1_(pt)
    case (I_GAMMA_1)
       dcoeff = 0._WP
    case (I_OMEGA_ROT)
       dcoeff = 0._WP
    end select

    ! Finish

    return

  end function dcoeff

  !****

  function dcoeff_V_2_ (this, pt) result (dcoeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: dcoeff

    ! Evaluate the logarithmic derivative of the V_2 coefficient

    dcoeff = this%coeff_V_2_(pt)*pt%x**2 + this%coeff_U_(pt) - 3._WP

    ! Finish

    return

  end function dcoeff_V_2_

  !****

  function dcoeff_As_ (this, pt) result (dcoeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: dcoeff

    ! Evaluate the logarithmic derivative of the As coefficient

    dcoeff = -(this%dcoeff_V_2_(pt)*pt%x**2 + 2._WP*this%coeff_V_2_(pt)*pt%x)/this%coeff_Gamma_1_(pt)

    ! Finish

    return

  end function dcoeff_As_

  !****

  function dcoeff_U_ (this, pt) result (dcoeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: dcoeff

    ! Evaluate the logarithmic derivative of the U coefficient, using
    ! eqn. (21) of Takata (2006) with dlnrho/dlnr = 0

    dcoeff = 3._WP - this%coeff_U_(pt)

    ! Finish

    return

  end function dcoeff_U_

  !****

  function dcoeff_c_1_ (this, pt) result (dcoeff)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    real(WP)                           :: dcoeff

    ! Evaluate the logarithmic derivative of the c_1 coefficient,
    ! using eqn. (20) of Takata (2006)

    dcoeff = 3._WP - this%coeff_U_(pt)

    ! Finish

    return

  end function dcoeff_c_1_

  !****

  function is_defined (this, i)

    class(parfait_model_t), intent(in) :: this
    integer, intent(in)                :: i
    logical                            :: is_defined

    $ASSERT_DEBUG(i >= 1 .AND. i <= I_LAST,Invalid index)

    ! Return the definition status of the i'th coefficient

    select case (i)
    case (I_V_2, I_AS, I_U, I_C_1, I_GAMMA_1, I_OMEGA_ROT)
       is_defined = .TRUE.
    case default
       is_defined = .FALSE.
    end select

    ! Finish

    return

  end function is_defined

  !****

  function is_vacuum (this, pt)

    class(parfait_model_t), intent(in) :: this
    type(point_t), intent(in)          :: pt
    logical                            :: is_vacuum

    $ASSERT_DEBUG(pt%s >= this%s_i .AND. pt%s <= this%s_o,Invalid segment)

    ! Return whether the point is a vacuum

    is_vacuum = (1._WP - pt%x**2) == 0._WP

    ! Finish

    return

  end function is_vacuum

  !****

  function Delta_p (this, x_i, x_o)

    class(parfait_model_t), intent(in) :: this
    real(WP), intent(in)               :: x_i
    real(WP), intent(in)               :: x_o
    real(WP)                           :: Delta_p

    ! Evaluate the dimensionless p-mode frequency separation

    $ABORT(Not yet implemented)

    ! Finish

    return

  end function Delta_p

  !****

  function Delta_g (this, x_i, x_o, lambda)

    class(parfait_model_t), intent(in) :: this
    real(WP), intent(in)               :: x_i
    real(WP), intent(in)               :: x_o
    real(WP), intent(in)               :: lambda
    real(WP)                           :: Delta_g

    ! Evaluate the dimensionless g-mode inverse period separation

    $ABORT(Not yet implemented)

    ! Finish

    return

  end function Delta_g

  !****

  function grid (this) result (gr)

    class(parfait_model_t), intent(in) :: this
    type(grid_t)                      :: gr

    ! Return the grid

    gr = this%gr

    ! Finish

    return

  end function grid

end module gyre_parfait_model
