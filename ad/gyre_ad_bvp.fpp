! Module   : gyre_ad_bvp
! Purpose  : solve adiabatic BVPs

$include 'core.inc'

module gyre_ad_bvp

  ! Uses

  use core_kinds

  use gyre_bvp
  use gyre_ad_shooter
  use gyre_ad_bound
  use gyre_sysmtx
  use gyre_ext_arith

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type, extends(bvp_t) :: ad_bvp_t
     private
     type(ad_shooter_t) :: sh
     type(ad_bound_t)   :: bd
     type(sysmtx_t)     :: sm
     integer, public    :: n
     integer, public    :: n_e
   contains 
     private
     procedure, public :: init
     procedure, public :: discrim
     procedure         :: shoot
     procedure, public :: recon
  end type ad_bvp_t

  ! Access specifiers

  private

  public :: ad_bvp_t

  ! Procedures

contains

  subroutine init (this, sh, bd)

    class(ad_bvp_t), intent(out)   :: this
    type(ad_shooter_t), intent(in) :: sh
    type(ad_bound_t), intent(in)   :: bd

    $CHECK_BOUNDS(bd%n_e,sh%n_e)

    ! Initialize the ad_bvp

    this%sh = sh
    this%bd = bd

    call this%sm%init(sh%n-1, sh%n_e, bd%n_i, bd%n_o)

    this%n = sh%n
    this%n_e = sh%n_e

    ! Finish

    return

  end subroutine init

!****

  function discrim (this, omega)

    class(ad_bvp_t), intent(inout) :: this
    complex(WP), intent(in)        :: omega
    type(ext_complex_t)            :: discrim

    ! Evaluate the discriminant as the determinant of the sysmtx

    call this%shoot(omega)

    discrim = this%sm%determinant()

    ! Finish

    return

  end function discrim

!****

  subroutine shoot (this, omega)

    class(ad_bvp_t), intent(inout) :: this
    complex(WP), intent(in)        :: omega

    ! Set up the sysmtx

    call this%sm%set_inner_bound(this%bd%inner_bound(omega))
    call this%sm%set_outer_bound(this%bd%outer_bound(omega))

    call this%sh%shoot(omega, this%sm)

    ! Finish

    return

  end subroutine shoot

!****

  subroutine recon (this, omega, x, y)

    class(ad_bvp_t), intent(inout)        :: this
    complex(WP), intent(in)               :: omega
    real(WP), allocatable, intent(out)    :: x(:)
    complex(WP), allocatable, intent(out) :: y(:,:)

    complex(WP) :: y_sh(this%n_e,this%n)

    ! Reconstruct the solution on the shooting grid

    call this%shoot(omega)

    y_sh = RESHAPE(this%sm%null_vector(), SHAPE(y_sh))

    ! Reconstruct the full solution

    call this%sh%recon(omega, y_sh, x, y)

    ! Finish

    return

  end subroutine recon

end module gyre_ad_bvp
