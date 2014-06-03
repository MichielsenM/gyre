! Module   : gyre_rad_bvp
! Purpose  : solve radial adiabatic BVPs
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

module gyre_rad_bvp

  ! Uses

  use core_kinds

  use gyre_bvp
  use gyre_model
  use gyre_cocache
  use gyre_modepar
  use gyre_oscpar
  use gyre_gridpar
  use gyre_numpar
  use gyre_discfunc
  use gyre_rad_shooter
  use gyre_jacobian
  use gyre_ivp
  use gyre_bound
  use gyre_sysmtx
  use gyre_ext_arith
  use gyre_grid
  use gyre_mode

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type, extends(bvp_t) :: rad_bvp_t
     private
     class(model_t), pointer        :: ml => null()
     type(cocache_t)                :: cc
     class(jacobian_t), allocatable :: jc
     class(ivp_t), allocatable      :: iv
     class(bound_t), allocatable    :: bd
     type(rad_shooter_t)            :: sh
     type(sysmtx_t)                 :: sm
     type(modepar_t)                :: mp
     type(oscpar_t)                 :: op
     type(numpar_t)                 :: np
     type(gridpar_t), allocatable   :: shoot_gp(:)
     type(gridpar_t), allocatable   :: recon_gp(:)
     real(WP), allocatable          :: x_in(:)
     real(WP), allocatable          :: x(:)
     integer, public                :: n
     integer, public                :: n_e
   contains 
     private
     $if ($GFORTRAN_PR57922)
     procedure, public :: final => final_
     $endif
     procedure         :: discrim_r_
     procedure         :: discrim_c_
     procedure         :: mode_r_
     procedure         :: mode_c_
     procedure         :: build_
     procedure         :: recon_
     procedure, public :: model => model_
  end type rad_bvp_t

  ! Interfaces

  interface rad_bvp_t
     module procedure rad_bvp_t_
  end interface rad_bvp_t

  ! Access specifiers

  private

  public :: rad_bvp_t

  ! Procedures

contains

  function rad_bvp_t_ (ml, mp, op, np, shoot_gp, recon_gp, x_in) result (bp)

    use gyre_rad_dziem_jacobian
    use gyre_rad_jcd_jacobian
    use gyre_rad_mix_jacobian

    use gyre_rad_zero_bound
    use gyre_rad_dziem_bound
    use gyre_rad_unno_bound
    use gyre_rad_jcd_bound

    use gyre_magnus_gl2_ivp
    use gyre_magnus_gl4_ivp
    use gyre_magnus_gl6_ivp
    use gyre_colloc_gl2_ivp
    use gyre_colloc_gl4_ivp
    use gyre_findiff_ivp

    class(model_t), pointer, intent(in) :: ml
    type(modepar_t), intent(in)         :: mp
    type(oscpar_t), intent(in)          :: op
    type(numpar_t), intent(in)          :: np
    type(gridpar_t), intent(in)         :: shoot_gp(:)
    type(gridpar_t), intent(in)         :: recon_gp(:)
    real(WP), allocatable, intent(in)   :: x_in(:)
    type(rad_bvp_t), target             :: bp

    integer               :: n
    real(WP), allocatable :: x_cc(:)

    $ASSERT(mp%l == 0,Invalid harmonic degree)

    ! Construct the rad_bvp_t

    ! Store parameters

    bp%mp = mp
    bp%op = op
    bp%np = np

    bp%shoot_gp = shoot_gp
    bp%recon_gp = recon_gp

    ! Set up the coefficient pointer
    
    bp%ml => ml

    ! Initialize the jacobian

    select case (op%variables_type)
    case ('DZIEM')
       allocate(bp%jc, SOURCE=rad_dziem_jacobian_t(bp%ml, bp%mp))
    case ('JCD')
       allocate(bp%jc, SOURCE=rad_jcd_jacobian_t(bp%ml, bp%mp))
    case ('MIX')
       allocate(bp%jc, SOURCE=rad_mix_jacobian_t(bp%ml, bp%mp))
    case default
       $ABORT(Invalid variables_type)
    end select

    ! Initialize the boundary conditions

    select case (bp%op%outer_bound_type)
    case ('ZERO')
       allocate(bp%bd, SOURCE=rad_zero_bound_t(bp%ml, bp%jc, bp%mp))
    case ('DZIEM')
       allocate(bp%bd, SOURCE=rad_dziem_bound_t(bp%ml, bp%jc, bp%mp))
    case ('UNNO')
       allocate(bp%bd, SOURCE=rad_unno_bound_t(bp%ml, bp%jc, bp%mp))
    case ('JCD')
       allocate(bp%bd, SOURCE=rad_jcd_bound_t(bp%ml, bp%jc, bp%mp))
    case default
       $ABORT(Invalid bound_type)
    end select

    ! Initialize the IVP solver

    select case (bp%np%ivp_solver_type)
    case ('MAGNUS_GL2')
       allocate(bp%iv, SOURCE=magnus_gl2_ivp_t(bp%jc))
    case ('MAGNUS_GL4')
       allocate(bp%iv, SOURCE=magnus_gl4_ivp_t(bp%jc))
    case ('MAGNUS_GL6')
       allocate(bp%iv, SOURCE=magnus_gl6_ivp_t(bp%jc))
    case ('COLLOC_GL2')
       allocate(bp%iv, SOURCE=colloc_gl2_ivp_t(bp%jc))
    case ('COLLOC_GL4')
       allocate(bp%iv, SOURCE=colloc_gl4_ivp_t(bp%jc))
    case ('FINDIFF')
       allocate(bp%iv, SOURCE=findiff_ivp_t(bp%jc))
    case default
       $ABORT(Invalid ivp_solver_type)
    end select

    ! Initialize the shooter

    bp%sh = rad_shooter_t(bp%ml, bp%iv, bp%np)

    ! Build the shooting grid

    call build_grid(bp%shoot_gp, bp%ml, bp%mp, x_in, bp%x, verbose=.TRUE.)

    n = SIZE(bp%x)

    ! Initialize the system matrix

    bp%sm = sysmtx_t(n-1, bp%jc%n_e, bp%bd%n_i, bp%bd%n_o)

    ! Other stuff

    if(ALLOCATED(x_in)) bp%x_in = x_in

    bp%n = n
    bp%n_e = bp%sh%n_e

    ! Set up the coefficient cache

    x_cc = [bp%x(1),bp%sh%abscissa(bp%x),bp%x(n)]

    call bp%ml%attach_cache(bp%cc)
    call bp%ml%fill_cache(x_cc)
    call bp%ml%detach_cache()

    ! Finish

    return

  end function rad_bvp_t_

!****

  $if ($GFORTRAN_PR57922)

  subroutine final_ (this)

    class(rad_bvp_t), intent(inout) :: this

    ! Finalize the rad_bvp_t

    call this%cc%final()
    call this%sm%final()

    deallocate(this%jc)
    deallocate(this%iv)
    deallocate(this%bd)

    deallocate(this%shoot_gp)
    deallocate(this%recon_gp)

    deallocate(this%x)
    deallocate(this%x_in)
    
    ! Finish

    return

  end subroutine final_

  $endif

!****

  function discrim_r_ (this, omega) result (discrim)

    class(rad_bvp_t), intent(inout) :: this
    real(WP), intent(in)            :: omega
    type(ext_real_t)                :: discrim

    type(ext_complex_t) :: discrim_c

    ! Evaluate the discriminant as the determinant of the sysmtx (real
    ! version)

    call this%build_(CMPLX(omega, KIND=WP))

    call this%sm%determinant(discrim_c, .TRUE., this%np%use_banded)

    discrim = ext_real_t(discrim_c)

    ! Finish

    return

  end function discrim_r_

!****

  function discrim_c_ (this, omega) result (discrim)

    class(rad_bvp_t), intent(inout) :: this
    complex(WP), intent(in)         :: omega
    type(ext_complex_t)             :: discrim

    ! Evaluate the discriminant as the determinant of the sysmtx
    ! (complex version)

    call this%build_(omega)

    call this%sm%determinant(discrim, .FALSE., this%np%use_banded)

    ! Finish

    return

  end function discrim_c_

!****

  function mode_r_ (this, omega) result (md)

    class(rad_bvp_t), target, intent(inout) :: this
    real(WP), intent(in)                    :: omega
    type(mode_t)                            :: md

    complex(WP)              :: omega_c
    real(WP), allocatable    :: x(:)
    complex(WP), allocatable :: y(:,:)
    real(WP)                 :: x_ref
    complex(WP)              :: y_ref(this%n_e)
    type(ext_complex_t)      :: discrim_c
    integer                  :: n
    integer                  :: i
    complex(WP), allocatable :: y_c(:,:)
    complex(WP)              :: y_c_ref(6)

    ! Reconstruct the solution

    omega_c = CMPLX(omega, KIND=WP)

    call this%recon_(omega_c, x, y, x_ref, y_ref, discrim_c, .TRUE.)

    ! Calculate canonical variables

    n = SIZE(x)

    allocate(y_c(6,n))

    !$OMP PARALLEL DO 
    do i = 1,n
       y_c(1:2,i) = MATMUL(this%jc%trans_matrix(x(i), omega_c, .TRUE.), y(:,i))
       y_c(3,i) = 0._WP
       y_c(4,i) = -y_c(1,i)*this%ml%U(x(i))
       y_c(5:6,i) = 0._WP
    end do

    y_c_ref(1:2) = MATMUL(this%jc%trans_matrix(x_ref, omega_c, .TRUE.), y_ref)
    y_c_ref(3) = 0._WP
    y_c_ref(4) = -y_c_ref(1)*this%ml%U(x_ref)
    y_c_ref(5:6) = 0._WP

    ! Initialize the mode

    md = mode_t(this%ml, this%mp, this%op, omega_c, discrim_c, x, y_c, x_ref, y_c_ref)

    ! Finish

    return

  end function mode_r_

!****

  function mode_c_ (this, omega) result (md)

    class(rad_bvp_t), target, intent(inout) :: this
    complex(WP), intent(in)                 :: omega
    type(mode_t)                            :: md

    real(WP), allocatable    :: x(:)
    complex(WP), allocatable :: y(:,:)
    real(WP)                 :: x_ref
    complex(WP)              :: y_ref(this%n_e)
    type(ext_complex_t)      :: discrim
    integer                  :: n
    integer                  :: i
    complex(WP), allocatable :: y_c(:,:)
    complex(WP)              :: y_c_ref(6)

    ! Reconstruct the solution

    call this%recon_(omega, x, y, x_ref, y_ref, discrim, .FALSE.)

    ! Calculate canonical variables

    n = SIZE(x)

    allocate(y_c(6,n))

    !$OMP PARALLEL DO 
    do i = 1,n
       y_c(1:2,i) = MATMUL(this%jc%trans_matrix(x(i), omega, .TRUE.), y(:,i))
       y_c(3,i) = 0._WP
       y_c(4,i) = -y_c(1,i)*this%ml%U(x(i))
       y_c(5:6,i) = 0._WP
    end do

    y_c_ref(1:2) = MATMUL(this%jc%trans_matrix(x_ref, omega, .TRUE.), y_ref)
    y_c_ref(3) = 0._WP
    y_c_ref(4) = -y_c_ref(1)*this%ml%U(x_ref)
    y_c_ref(5:6) = 0._WP

    ! Initialize the mode

    md = mode_t(this%ml, this%mp, this%op, omega, discrim, x, y_c, x_ref, y_c_ref)

    ! Finish

    return

  end function mode_c_

!****

  subroutine build_ (this, omega)

    class(rad_bvp_t), target, intent(inout) :: this
    complex(WP), intent(in)                 :: omega

    ! Set up the sysmtx

    call this%ml%attach_cache(this%cc)

    call this%sm%set_inner_bound(this%bd%inner_bound(this%x(1), omega), ext_complex_t(1._WP))
    call this%sm%set_outer_bound(this%bd%outer_bound(this%x(this%n), omega), ext_complex_t(1._WP))

    call this%sh%shoot(omega, this%x, this%sm)

    call this%ml%detach_cache()

    call this%sm%scale_rows()

    ! Finish

    return

  end subroutine build_

!****

  subroutine recon_ (this, omega, x, y, x_ref, y_ref, discrim, use_real)

    class(rad_bvp_t), intent(inout)       :: this
    complex(WP), intent(in)               :: omega
    real(WP), allocatable, intent(out)    :: x(:)
    complex(WP), allocatable, intent(out) :: y(:,:)
    real(WP), intent(out)                 :: x_ref
    complex(WP), intent(out)              :: y_ref(:)
    type(ext_complex_t), intent(out)      :: discrim
    logical, optional, intent(in)         :: use_real

    complex(WP) :: b(this%n_e*this%n)
    complex(WP) :: y_sh(this%n_e,this%n)
    logical     :: same_grid
    complex(WP) :: y_ref_(this%n_e,1)

    $CHECK_BOUNDS(SIZE(y_ref),this%n_e)

    ! Reconstruct the solution on the shooting grid

    call this%build_(omega)

    call this%sm%null_vector(b, discrim, use_real, this%np%use_banded)

    y_sh = RESHAPE(b, SHAPE(y_sh))

    ! Build the recon grid

    this%recon_gp%omega_a = REAL(omega)
    this%recon_gp%omega_b = REAL(omega)

    call build_grid(this%recon_gp, this%ml, this%mp, this%x, x)

    if(SIZE(x) == SIZE(this%x)) then
       same_grid = ALL(x == this%x)
    else
       same_grid = .FALSE.
    endif

    ! Reconstruct the full solution

    if(same_grid) then

       y = y_sh

    else

       allocate(y(this%n_e,SIZE(x)))

       call this%sh%recon(omega, this%x, y_sh, x, y)

    endif

    ! Reconstruct the solution at x_ref
    
    x_ref = MIN(MAX(this%op%x_ref, this%x(1)), this%x(this%n))

    call this%sh%recon(omega, this%x, y_sh, [x_ref], y_ref_)

    y_ref = y_ref_(:,1)

    ! Finish

    return

  end subroutine recon_

!****

  function model_ (this) result (ml)

    class(rad_bvp_t), intent(in) :: this
    class(model_t), pointer      :: ml

    ! Return the model pointer

    ml => this%ml

    ! Finish

    return

  end function model_

end module gyre_rad_bvp
