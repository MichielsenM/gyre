! Module   : gyre_sad_bvp
! Purpose  : static adiabatic bounary value problem solver
!
! Copyright 2019-2021 Rich Townsend & The GYRE Team
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

module gyre_sad_bvp

  ! Uses

  use core_kinds

  use gyre_bvp
  use gyre_context
  use gyre_ext
  use gyre_grid
  use gyre_interp
  use gyre_model
  use gyre_mode_par
  use gyre_num_par
  use gyre_osc_par
  use gyre_point
  use gyre_sad_bound
  use gyre_sad_diff
  use gyre_sad_trans
  use gyre_state
  use gyre_util
  use gyre_wave

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type, extends (r_bvp_t) :: sad_bvp_t
     private
     type(context_t), pointer :: cx => null()
     type(grid_t)             :: gr
     type(sad_trans_t)        :: tr
     type(mode_par_t)         :: md_p
     type(num_par_t)          :: nm_p
     type(osc_par_t)          :: os_p
  end type sad_bvp_t

  ! Interfaces

  interface sad_bvp_t
     module procedure sad_bvp_t_
  end interface sad_bvp_t

  interface wave_t
     module procedure wave_t_hom_
     module procedure wave_t_inhom_
  end interface wave_t

  ! Access specifiers

  private

  public :: sad_bvp_t
  public :: wave_t

  ! Procedures

contains

  function sad_bvp_t_ (cx, gr, md_p, nm_p, os_p) result (bp)

    type(context_t), pointer, intent(in) :: cx
    type(grid_t), intent(in)             :: gr
    type(mode_par_t), intent(in)         :: md_p
    type(num_par_t), intent(in)          :: nm_p
    type(osc_par_t), intent(in)          :: os_p
    type(sad_bvp_t)                      :: bp

    type(point_t)                 :: pt_i
    type(point_t)                 :: pt_o
    type(sad_bound_t)             :: bd
    integer                       :: k
    type(sad_diff_t), allocatable :: df(:)

    ! Construct the sad_bvp_t

    if (os_p%alpha_grv /= 1._WP) then
       $WARN(alpha_grv is ignored in static equations)
    endif
    
    pt_i = gr%pt_i()
    pt_o = gr%pt_o()

    ! Initialize the boundary conditions

    bd = sad_bound_t(cx, md_p, os_p)

    ! Initialize the difference equations

    allocate(df(gr%n_k-1))

    !$OMP PARALLEL DO
    do k = 1, gr%n_k-1
       df(k) = sad_diff_t(cx, gr%pt(k), gr%pt(k+1), md_p, nm_p, os_p)
    end do

    ! Initialize the bvp_t

    bp%r_bvp_t = r_bvp_t_(bd, df, nm_p) 

    ! Other initializations

    bp%cx => cx
    bp%gr = gr

    bp%tr = sad_trans_t(cx, md_p, os_p)
    call bp%tr%stencil(gr%pt)

    bp%md_p = md_p
    bp%md_p%static = .TRUE.

    bp%nm_p = nm_p
    bp%os_p = os_p

    ! Finish

    return

  end function sad_bvp_t_

  !****

  function wave_t_hom_ (bp, st, j) result (wv)

    class(sad_bvp_t), intent(inout) :: bp
    type(r_state_t), intent(in)     :: st
    integer, intent(in)             :: j
    type(wave_t)                    :: wv

    real(WP) :: y(2,bp%n_k)
    integer  :: k

    ! Calculate the solution vector

    call bp%build(st)
    call bp%factor()

    y = bp%soln_vec_hom()

    ! Convert to canonical form

    !$OMP PARALLEL DO
    do k = 1, bp%n_k
       call bp%tr%trans_vars(y(:,k), k, st, from=.FALSE.)
    end do

    ! Construct the wave_t

    wv = wave_t_y_(bp, st, y, j)

    ! Finish

    return

  end function wave_t_hom_

  !****

  function wave_t_inhom_ (bp, st, z_i, z_o, j) result (wv)

    class(sad_bvp_t), intent(inout) :: bp
    type(r_state_t), intent(in)     :: st
    real(WP), intent(in)            :: z_i(:)
    real(WP), intent(in)            :: z_o(:)
    integer, intent(in)             :: j
    type(wave_t)                    :: wv

    real(WP) :: y(2,bp%n_k)
    integer  :: k

    $CHECK_BOUNDS(SIZE(z_i),bp%n_i)
    $CHECK_BOUNDS(SIZE(z_o),bp%n_o)

    ! Calculate the solution vector

    call bp%build(st)
    call bp%factor()

    y = bp%soln_vec_inhom(z_i, z_o)

    ! Convert to canonical form

    !$OMP PARALLEL DO
    do k = 1, bp%n_k
       call bp%tr%trans_vars(y(:,k), k, st, from=.FALSE.)
    end do

    ! Construct the wave_t

    wv = wave_t_y_(bp, st, y, j)

    ! Finish

    return

  end function wave_t_inhom_

  !****

  function wave_t_y_ (bp, st, y, j) result (wv)

    class(sad_bvp_t), intent(inout) :: bp
    type(r_state_t), intent(in)     :: st
    real(WP), intent(in)            :: y(:,:)
    integer, intent(in)             :: j
    type(wave_t)                    :: wv

    complex(WP)     :: y_c(6,bp%n_k)
    type(c_state_t) :: st_c
    type(c_ext_t)   :: discrim

    ! Set up complex eigenfunctions

    st_c = c_state_t(CMPLX(st%omega, KIND=WP), st%omega)

    y_c(1,:) = -y(1,:)
    y_c(2,:) = -y(1,:)
    y_c(3,:) = y(1,:)
    y_c(4,:) = y(2,:)
    y_c(5,:) = 0._WP
    y_c(6,:) = 0._WP

    ! Construct the wave_t

    discrim = c_ext_t(bp%det())

    wv = wave_t(st_c, y_c, discrim, bp%cx, bp%gr, bp%md_p, bp%nm_p, bp%os_p, j)

    ! Finish

    return

  end function wave_t_y_

end module gyre_sad_bvp
