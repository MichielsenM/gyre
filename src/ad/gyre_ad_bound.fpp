! Incfile  : gyre_ad_bound
! Purpose  : boundary conditions (adiabatic)
!
! Copyright 2013-2015 Rich Townsend
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

module gyre_ad_bound

  ! Uses

  use core_kinds

  use gyre_ad_vars
  use gyre_atmos
  use gyre_bound
  use gyre_ad_eqns
  use gyre_model
  use gyre_osc_par
  use gyre_rot

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Parameter definitions

  integer, parameter :: INNER_REGULAR_TYPE = 1
  integer, parameter :: INNER_ZERO_TYPE = 2
  integer, parameter :: OUTER_ZERO_TYPE = 3
  integer, parameter :: OUTER_DZIEM_TYPE = 4
  integer, parameter :: OUTER_UNNO_TYPE = 5
  integer, parameter :: OUTER_JCD_TYPE = 6

  ! Derived-type definitions

  type, extends (r_bound_t) :: ad_bound_t
     private
     class(model_seg_t), pointer :: ms => null()
     class(r_rot_t), allocatable :: rt
     type(ad_vars_t)             :: vr
     real(WP)                    :: x
     integer                     :: type
     logical                     :: cowling_approx
   contains 
     private
     procedure, public :: build => build_
     procedure         :: build_inner_regular_
     procedure         :: build_inner_zero_
     procedure         :: build_outer_zero_
     procedure         :: build_outer_dziem_
  end type ad_bound_t

  ! Interfaces

  interface ad_bound_t
     module procedure ad_bound_t_
  end interface ad_bound_t

  ! Access specifiers

  private

  public :: ad_bound_t

  ! Procedures

contains

  function ad_bound_t_ (ms, md_p, os_p, x, inner) result (bd)

    class(model_seg_t), pointer, intent(in) :: ms
    type(mode_par_t), intent(in)            :: md_p
    type(osc_par_t), intent(in)             :: os_p
    real(WP), intent(in)                    :: x
    logical, intent(in)                     :: inner
    type(ad_bound_t)                        :: bd

    ! Construct the ad_bound_t

    bd%ms => ms
    
    allocate(bd%rt, SOURCE=r_rot_t(ms, md_p, os_p))
    bd%vr = ad_vars_t(ms, md_p, os_p)

    bd%x = x

    if (inner) then

       select case (op%inner_bound)
       case ('REGULAR')
          bd%type = INNER_REGULAR_TYPE
       case ('ZERO')
          bd%type = INNER_ZERO_TYPE
       case default
          $ABORT(Invalid inner_bound)
       end select

    else

       select case (op%outer_bound)
       case ('ZERO')
          bd%type = OUTER_ZERO_TYPE
       case ('DZIEM')
          bd%type = OUTER_DZIEM_TYPE
       case ('UNNO')
          bd%type = OUTER_UNNO_TYPE
       case ('JCD')
          bd%type = OUTER_JCD_TYPE
       case default
          $ABORT(Invalid outer_bound)
       end select

    endif

    bd%cowling_approx = op%cowling_approx

    bd%n = 2
    bd%n_e = 4

    ! Finish

    return
    
  end function ad_bound_t_

!****

  subroutine build_ (this, omega, E, S)

    class(ad_bound_t), intent(in) :: this
    real(WP), intent(in)          :: omega
    real(WP), intent(out)         :: E(:,:)
    type(${T}_ext_t), intent(out) :: S

    $CHECK_BOUNDS(SIZE(E, 1),this%n)
    $CHECK_BOUNDS(SIZE(E, 2),this%n_e)
    
    ! Evaluate the boundary conditions

    select case (this%type)
    case (INNER_REGULAR_TYPE)
       call this%build_inner_regular_(omega, E, S)
    case (INNER_ZERO_TYPE)
       call this%build_inner_zero_(omega, E, S)
    case (OUTER_ZERO_TYPE)
       call this%build_outer_zero_(omega, E, S)
    case (OUTER_DZIEM_TYPE)
       call this%build_outer_dziem_(omega, E, S)
    case (OUTER_UNNO_TYPE)
       call this%build_outer_unno_(omega, E, S)
    case (OUTER_JCD_TYPE)
       call this%build_outer_jcd_(omega, E, S)
    case default
       $ABORT(Invalid type_i)
    end select

    ! Apply the variables transformation

    E = MATMUL(E, this%vr%T(this%x, omega))

    ! Finish

    return

  end subroutine build_

!****

  subroutine build_inner_regular_ (this, omega, E, S)

    class(ad_bound_t), intent(in) :: this
    real(WP), intent(in)          :: omega
    real(WP), intent(out)         :: E(:,:)
    type(${T}_ext_t), intent(out) :: S

    real(WP) :: c_1
    real(WP) :: l_e
    real(WP) :: omega_c
    real(WP) :: alpha_gr

    $CHECK_BOUNDS(SIZE(E, 1),this%n)
    $CHECK_BOUNDS(SIZE(E, 2),this%n_e)
    
    $ASSERT(this%x == 0._WP,Boundary condition invalid for x /= 0)

    ! Evaluate the inner boundary conditions (regular-enforcing)

    ! Calculate coefficients

    c_1 = this%ms%c_1(this%x)

    l_e = this%rt%l_e(this%x, omega)

    omega_c = this%rt%omega_c(this%x, omega)

    if (this%cowling_approx) then
       alpha_gr = 0._WP
    else
       alpha_gr = 1._WP
    endif

    ! Set up the boundary conditions

    E(1,1) = c_1*omega_c**2
    E(1,2) = -l_e
    E(1,3) = alpha_gr*(0._WP)
    E(1,4) = alpha_gr*(0._WP)
        
    E(2,1) = alpha_gr*(0._WP)
    E(2,2) = alpha_gr*(0._WP)
    E(2,3) = alpha_gr*(l_e)
    E(2,4) = alpha_gr*(-1._WP) + (1._WP - alpha_gr)

    S = r_ext_t(1._WP)

    ! Finish

    return

  end subroutine build_inner_regular_

!****

  subroutine build_inner_zero_ (this, omega, E, S)

    class(ad_bound_t), intent(in) :: this
    real(WP), intent(in)          :: omega
    real(WP), intent(out)         :: E(:,:)
    type(${T}_ext_t), intent(out) :: S

    real(WP) :: alpha_gr

    $CHECK_BOUNDS(SIZE(E, 1),this%n)
    $CHECK_BOUNDS(SIZE(E, 2),this%n_e)

    $ASSERT(this%x /= 0._WP,Boundary condition invalid for x == 0)

    ! Evaluate the inner boundary conditions (zero
    ! displacement/gravity)

    ! Calculate coefficients

    if (this%cowling_approx) then
       alpha_gr = 0._WP
    else
       alpha_gr = 1._WP
    endif

    ! Set up the boundary conditions

    E(1,1) = 1._WP
    E(1,2) = 0._WP
    E(1,3) = alpha_gr*(0._WP)
    E(1,4) = alpha_gr*(0._WP)
        
    E(2,1) = alpha_gr*(0._WP)
    E(2,2) = alpha_gr*(0._WP)
    E(2,3) = alpha_gr*(0._WP)
    E(2,4) = alpha_gr*(1._WP) + (1._WP - alpha_gr)

    S = r_ext_t(1._WP)
      
    ! Finish

    return

  end subroutine build_inner_zero_

!****

  subroutine build_outer_zero_ (this, omega, E, S)

    class(ad_bound_t), intent(in) :: this
    real(WP), intent(in)          :: omega
    real(WP), intent(out)         :: E(:,:)
    type(${T}_ext_t), intent(out) :: S

    real(WP) :: U
    real(WP) :: l_e
    real(WP) :: alpha_gr

    $CHECK_BOUNDS(SIZE(E, 1),this%n)
    $CHECK_BOUNDS(SIZE(E, 2),this%n_e)

    ! Evaluate the outer boundary conditions (zero-pressure)

    ! Calculate coefficients

    U = this%ms%U(this%x)

    l_e = this%rt%l_e(this%x, omega)

    if (this%cowling_approx) then
       alpha_gr = 0._WP
    else
       alpha_gr = 1._WP
    endif

    ! Set up the boundary conditions

    E(1,1) = 1._WP
    E(1,2) = -1._WP
    E(1,3) = alpha_gr*(1._WP)
    E(1,4) = alpha_gr*(0._WP)
      
    E(2,1) = alpha_gr*(U)
    E(2,2) = alpha_gr*(0._WP)
    E(2,3) = alpha_gr*(l_e + 1._WP) + (1._WP - alpha_gr)
    E(2,4) = alpha_gr*(1._WP)

    S = r_ext_t(1._WP)

    ! Finish

    return

  end subroutine build_outer_zero_

!****

  subroutine build_outer_dziem_ (this, omega, E, S)

    class(ad_bound_t), intent(in) :: this
    real(WP), intent(in)          :: omega
    real(WP), intent(out)         :: E(:,:)
    type(${T}_ext_t), intent(out) :: S

    real(WP) :: V
    real(WP) :: c_1
    real(WP) :: lambda
    real(WP) :: l_e
    real(WP) :: omega_c
    real(WP) :: alpha_gr

    $CHECK_BOUNDS(SIZE(E, 1),this%n)
    $CHECK_BOUNDS(SIZE(E, 2),this%n_e)

    ! Evaluate the outer boundary conditions ([Dzi1971] formulation)

    ! Calculate coefficients

    V = this%ms%V_2(this%x)*this%x**2
    c_1 = this%ms%c_1(this%x)

    lambda = this%rt%lambda(this%x, omega)
    l_e = this%rt%l_e(this%x, omega)

    omega_c = this%rt%omega_c(this%x, omega)

    if (this%cowling_approx) then
       alpha_gr = 0._WP
    else
       alpha_gr = 1._WP
    endif

    ! Set up the boundary conditions

    E(1,1) = 1 + (lambda/(c_1*omega_c**2) - 4._WP - c_1*omega_c**2)/V
    E(1,2) = -1._WP
    E(1,3) = alpha_gr*(1 + (lambda/(c_1*omega_c**2) - l_e - 1._WP)/V)
    E(1,4) = alpha_gr*(0._WP)
      
    E(2,1) = alpha_gr*(0._WP)
    E(2,2) = alpha_gr*(0._WP)
    E(2,3) = alpha_gr*(l_e + 1._WP) + (1._WP - alpha_gr)
    E(2,4) = alpha_gr*(1._WP)

    S = r_ext_t(1._WP)

    ! Finish

    return

  end subroutine build_outer_dziem_

!****

  subroutine build_outer_unno_ (this, omega, E, S)

    class(ad_bound_t), intent(in) :: this
    real(WP), intent(in)          :: omega
    real(WP), intent(out)         :: E(:,:)
    type(${T}_ext_t), intent(out) :: S

    real(WP) :: V_g
    real(WP) :: As
    real(WP) :: c_1
    real(WP) :: lambda
    real(WP) :: l_e
    real(WP) :: omega_c
    real(WP) :: beta
    real(WP) :: alpha_gr
    real(WP) :: b_11
    real(WP) :: b_12
    real(WP) :: b_13
    real(WP) :: b_21
    real(WP) :: b_22
    real(WP) :: b_23
    real(WP) :: alpha_1
    real(WP) :: alpha_2

    $CHECK_BOUNDS(SIZE(E, 1),this%n)
    $CHECK_BOUNDS(SIZE(E, 2),this%n_e)

    ! Evaluate the outer boundary conditions ([Unn1989] formulation)

    ! Calculate coefficients

    call eval_atmos_coeffs_unno(this%ms, this%x, V_g, As, c_1)

    lambda = this%rt%lambda(this%x, omega)
    l_e = this%rt%l_e(this%x, omega)

    omega_c = this%rt%omega_c(this%x, omega)

    beta = atmos_beta(V_g, As, c_1, omega_c, lambda)

    if (this%cowling_approx) then
       alpha_gr = 0._WP
    else
       alpha_gr = 1._WP
    endif
      
    b_11 = V_g - 3._WP
    b_12 = lambda/(c_1*omega_c**2) - V_g
    b_13 = alpha_gr*(V_g)

    b_21 = c_1*omega_c**2 - As
    b_22 = 1._WP + As
    b_23 = alpha_gr*(-As)
    
    alpha_1 = (b_12*b_23 - b_13*(b_22+l_e))/((b_11+l_e)*(b_22+l_e) - b_12*b_21)
    alpha_2 = (b_21*b_13 - b_23*(b_11+l_e))/((b_11+l_e)*(b_22+l_e) - b_12*b_21)

    ! Set up the boundary conditions

    E(1,1) = beta - b_11
    E(1,2) = -b_12
    E(1,3) = -(alpha_1*(beta - b_11) - alpha_2*b_12)
    E(1,4) = 0._WP

    E(2,1) = alpha_gr*(0._WP)
    E(2,2) = alpha_gr*(0._WP)
    E(2,3) = alpha_gr*(l_e + 1._WP) + (1._WP - alpha_gr)
    E(2,4) = alpha_gr*(1._WP)

    S = r_ext_t(1._WP)

    ! Finish

    return

  end subroutine build_outer_unno_

!****

  subroutine build_outer_jcd_ (this, omega, E, S)

    class(ad_bound_t), intent(in) :: this
    real(WP), intent(in)          :: omega
    real(WP), intent(out)         :: E(:,:)
    type(${T}_ext_t), intent(out) :: S

    real(WP) :: V_g
    real(WP) :: As
    real(WP) :: c_1
    real(WP) :: lambda
    real(WP) :: l_e
    real(WP) :: omega_c
    real(WP) :: beta
    real(WP) :: alpha_gr
    real(WP) :: b_11
    real(WP) :: b_12

    $CHECK_BOUNDS(SIZE(E, 1),this%n)
    $CHECK_BOUNDS(SIZE(E, 2),this%n_e)

    ! Evaluate the outer boundary conditions ([Chr2008] formulation)

    call eval_atmos_coeffs_jcd(this%ms, this%x, V_g, As, c_1)

    ! Calculate coefficients

    lambda = this%rt%lambda(this%x, omega)
    l_e = this%rt%l_e(this%x, omega)

    omega_c = this%rt%omega_c(this%x, omega)

    beta = atmos_beta(V_g, As, c_1, omega_c, lambda)

    if (this%cowling_approx) then
       alpha_gr = 0._WP
    else
       alpha_gr = 1._WP
    endif
      
    b_11 = V_g - 3._WP
    b_12 = lambda/(c_1*omega_c**2) - V_g

    ! Set up the boundary conditions

    E(1,1) = beta - b_11
    E(1,2) = -b_12
    E(1,3) = alpha_gr*(b_12 + (lambda/(c_1*omega_c**2) - l_e - 1._WP)*b_12/(V_g + As))
    E(1,4) = alpha_gr*(0._WP)

    E(2,1) = alpha_gr*(0._WP)
    E(2,2) = alpha_gr*(0._WP)
    E(2,3) = alpha_gr*(l_e + 1._WP) + (1._WP - alpha_gr)
    E(2,4) = alpha_gr*(1._WP)

    S = r_ext_t(1._WP)

    ! Finish

    return

  end subroutine build_outer_jcd_

end module gyre_ad_bound
