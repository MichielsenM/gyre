! Module   : gyre_summary
! Purpose  : summary output
!
! Copyright 2020-2022 Rich Townsend & The GYRE Team
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
$include 'gyre_output.inc'
$include 'gyre_summary.inc'
  
module gyre_summary

  ! Uses

  use core_kinds
  use core_memory
  use core_string

  use gyre_context
  use gyre_constants
  use gyre_evol_model
  use gyre_grid
  use gyre_hdf_writer
  use gyre_mode
  use gyre_model
  use gyre_out_par
  use gyre_out_util
  use gyre_resp
  use gyre_state
  use gyre_txt_writer
  use gyre_util
  use gyre_wave
  use gyre_writer

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Parameter definitions

  integer, parameter :: TYPE_I = 1
  integer, parameter :: TYPE_R = 2
  integer, parameter :: TYPE_C = 3
  integer, parameter :: TYPE_A = 4
  integer, parameter :: TYPE_M = 5

  integer, parameter :: DATA_LEN = 25

  integer, parameter :: D_0 = 128

  ! Derived-type definitions

  type :: summary_col_t
     integer, allocatable             :: data_i(:)
     real(WP), allocatable            :: data_r(:)
     complex(WP), allocatable         :: data_c(:)
     character(DATA_LEN), allocatable :: data_a(:)
     character(ITEM_LEN)              :: item
     integer                          :: type = 0
     integer                          :: n = 0
   contains
     procedure :: append_r_
     procedure :: append_c_
     procedure :: append_i_
     procedure :: append_a_
     generic   :: append => append_r_, append_c_, append_i_, append_a_
  end type summary_col_t

  type :: summary_t
     private
     type(out_par_t)                  :: ot_p
     character(ITEM_LEN), allocatable :: items(:)
     type(summary_col_t), allocatable :: sc(:)
     integer                          :: n_row = 0
   contains
     private
     procedure, public :: write
     procedure, public :: cache
  end type summary_t

  ! Interfaces

  interface summary_t
     module procedure summary_t_
  end interface summary_t

  ! Access specifiers

  private

  public :: summary_t

contains

  function summary_t_ (ot_p) result (sm)

    type(out_par_t), intent(in) :: ot_p
    type(summary_t)             :: sm

    character(ITEM_LEN), allocatable :: items(:)
    integer                          :: n
    character(ITEM_LEN), allocatable :: items_glb(:)
    character(ITEM_LEN), allocatable :: items_col(:)
    integer                          :: n_glb
    integer                          :: n_col
    integer                          :: i
    logical                          :: global

    ! Construct the summary_t

    sm%ot_p = ot_p

    ! Split up the items list, and separate it into
    ! global and column items

    items = split_list(ot_p%summary_item_list, ',', unique=.TRUE.)

    n = SIZE(items)

    allocate(items_glb(n))
    allocate(items_col(n))

    n_glb = 0
    n_col = 0

    item_loop : do i = 1, n

       select case (items(i))
       case ('n_row', 'freq_units', 'freq_frame', &
             'G_GRAVITY', 'C_LIGHT', 'A_RADIATION', &
             'M_SUN', 'R_SUN', 'L_SUN')
          global = .TRUE.
       case default
          global = .FALSE.
       end select

       if (global) then
          n_glb = n_glb + 1
          items_glb(n_glb) = items(i)
       else
          n_col = n_col + 1
          items_col(n_col) = items(i)
       end if

    end do item_loop

    ! Set up columns

    allocate(sm%sc(n_col))

    sm%sc%item = items_col(:n_col)

    ! Other initializations

    sm%items = items_glb(:n_glb)

    sm%n_row = 0

    ! Finish

  end function summary_t_

  !****

  subroutine write (this)

    class(summary_t), intent(in) :: this

    class(writer_t), allocatable :: wr
    integer                      :: i

    ! Write a summary file

    if (this%n_row == 0 .OR. SIZE(this%sc) == 0) return

    ! Open the file

    select case (this%ot_p%summary_file_format)
    case ('HDF')
       allocate(wr, SOURCE=hdf_writer_t(this%ot_p%summary_file, this%ot_p%label))
    case ('TXT')
       allocate(wr, SOURCE=txt_writer_t(this%ot_p%summary_file, this%ot_p%label))
    case default
       $ABORT(Invalid summary_file_format)
    end select

    ! Write the global data

    global_item_loop : do i = 1, SIZE(this%items)

       select case (this%items(i))

       $WRITE_VALUE(n_row,this%n_row)
       $WRITE_VALUE(freq_units,this%ot_p%freq_units)
       $WRITE_VALUE(freq_frame,this%ot_p%freq_frame)
       $WRITE_VALUE(G_GRAVITY,G_GRAVITY)
       $WRITE_VALUE(C_LIGHT,C_LIGHT)
       $WRITE_VALUE(A_RADIATION,A_RADIATION)
       $WRITE_VALUE(M_SUN,M_SUN)
       $WRITE_VALUE(R_SUN,R_SUN)
       $WRITE_VALUE(L_SUN,L_SUN)

       end select

    end do global_item_loop

    ! Write the cached column data
    
    column_item_loop : do i = 1, SIZE(this%sc)

       associate (sc => this%sc(i))

         select case (sc%type)
         case (TYPE_M)
            ! Missing item; do nothing
         case (TYPE_I)
            call wr%write(sc%item, sc%data_i(:sc%n))
         case (TYPE_R)
            call wr%write(sc%item, sc%data_r(:sc%n))
         case (TYPE_C)
            call wr%write(sc%item, sc%data_c(:sc%n))
         case (TYPE_A)
            call wr%write(sc%item, sc%data_a(:sc%n))
         case default
            $ABORT(Invalid column type)
         end select

       end associate

    end do column_item_loop

    ! Close the file

    call wr%final()

    ! Finish

    return

  end subroutine write

  !****

  subroutine cache (this, wv)

    class(summary_t), intent(inout) :: this
    class(wave_t), intent(in)       :: wv

    type(context_t)         :: cx
    class(model_t), pointer :: ml
    type(c_state_t)         :: st
    type(grid_t)            :: gr
    integer                 :: i
    logical                 :: cached
    logical, save           :: first = .TRUE.

    ! Cache summary data

    if (this%ot_p%summary_file == '') return

    if (filter_wave(wv, this%ot_p%summary_filter_list)) return

    ! Cache the items

    cx = wv%context()
    ml => cx%model()

    st = wv%state()
    gr = wv%grid()

    item_loop : do i = 1, SIZE(this%sc)

       call cache_wave_(this%ot_p, wv, gr, this%sc(i), cached)
       if (cached) cycle item_loop

       call cache_context_(this%ot_p, cx, gr, wv%j_ref, this%sc(i), cached)
       if (cached) cycle item_loop

       call cache_model_(this%ot_p, ml, gr, wv%l, this%sc(i), cached)
       if (cached) cycle item_loop

       ! Indicate a problem with the caching

       this%sc(i)%type = TYPE_M

       if (first) then
          write(ERROR_UNIT, *) 'Ignoring missing/invalid summary item:', TRIM(this%sc(i)%item)
       endif

    end do item_loop

    if (first) first = .FALSE.

    this%n_row = this%n_row + 1

    ! Finish

  end subroutine cache

  !****

  subroutine cache_wave_ (ot_p, wv, gr, sc, cached)

    type(out_par_t), intent(in)        :: ot_p
    class(wave_t), intent(in)          :: wv
    type(grid_t), intent(in)           :: gr
    type(summary_col_t), intent(inout) :: sc
    logical, intent(out)               :: cached

    ! Cache the item from wave_t data

    cached = .TRUE.

    select case (sc%item)
       
    $CACHE_VALUE(n,wv%n)
    $CACHE_VALUE(id,wv%id)
    $CACHE_VALUE(l,wv%l)
    $CACHE_VALUE(l_i,wv%l_i)
    $CACHE_VALUE(m,wv%m)
    $CACHE_VALUE(omega,wv%omega)
    $CACHE_VALUE(freq,wv%freq(ot_p%freq_units, ot_p%freq_frame))
    $CACHE_VALUE(dfreq_rot,wv%dfreq_rot(ot_p%freq_units))
    $CACHE_VALUE(freq_units,ot_p%freq_units)
    $CACHE_VALUE(freq_frame,ot_p%freq_frame)
    $CACHE_VALUE(x_ref,gr%pt(wv%j_ref)%x)
    $CACHE_VALUE(dx_min,wv%dx_min())
    $CACHE_VALUE(dx_max,wv%dx_max())
    $CACHE_VALUE(dx_rms,wv%dx_rms())
    $CACHE_VALUE(omega_int,wv%omega_int())
    $CACHE_VALUE(domega_rot,wv%domega_rot())
    $CACHE_VALUE(eta,wv%eta())
    $CACHE_VALUE(f_T,wv%f_T())
    $CACHE_VALUE(f_g,wv%f_g())
    $CACHE_VALUE(psi_T,wv%psi_T())
    $CACHE_VALUE(psi_g,wv%psi_g())
    $CACHE_VALUE(E,wv%E())
    $CACHE_VALUE(E_p,wv%E_p())
    $CACHE_VALUE(E_g,wv%E_g())
    $CACHE_VALUE(E_norm,wv%E_norm())
    $CACHE_VALUE(E_ratio,wv%E_ratio())
    $CACHE_VALUE(H,wv%H())
    $CACHE_VALUE(W,wv%W())
    $CACHE_VALUE(W_eps,wv%W_eps())
    $CACHE_VALUE(Q,wv%Q())
    $CACHE_VALUE(tau_ss,wv%tau_ss())
    $CACHE_VALUE(tau_tr,wv%tau_tr())
    $CACHE_VALUE(zeta,wv%zeta())
    $CACHE_VALUE(beta,wv%beta())
    $CACHE_VALUE(xi_r_ref,wv%xi_r(wv%j_ref))
    $CACHE_VALUE(xi_h_ref,wv%xi_h(wv%j_ref))
    $CACHE_VALUE(eul_Phi_ref,wv%eul_Phi(wv%j_ref))
    $CACHE_VALUE(deul_Phi_ref,wv%deul_Phi(wv%j_ref))
    $CACHE_VALUE(lag_S_ref,wv%lag_S(wv%j_ref))
    $CACHE_VALUE(lag_L_ref,wv%lag_L(wv%j_ref))

    case default

       select type (wv)

       class is (mode_t)

          call cache_mode_(ot_p, wv, gr, sc, cached)

       class is (resp_t)

          call cache_resp_(ot_p, wv, gr, sc, cached)

       class default

          cached = .FALSE.

       end select

    end select

    ! Finish

    return

  end subroutine cache_wave_
      
  !****

  subroutine cache_mode_ (ot_p, md, gr, sc, cached)

    type(out_par_t), intent(in)        :: ot_p
    class(mode_t), intent(in)          :: md
    type(grid_t), intent(in)           :: gr
    type(summary_col_t), intent(inout) :: sc
    logical, intent(out)               :: cached

    ! Cache the item from mode_t data

    cached = .TRUE.

    select case (sc%item)

    $CACHE_VALUE(n_p,md%n_p)
    $CACHE_VALUE(n_g,md%n_g)
    $CACHE_VALUE(n_pg,md%n_pg)

    case default

       cached = .FALSE.
         
    end select

    ! Finish

    return

  end subroutine cache_mode_

  !****

  subroutine cache_resp_ (ot_p, rs, gr, sc, cached)

    type(out_par_t), intent(in)        :: ot_p
    class(resp_t), intent(in)          :: rs
    type(grid_t), intent(in)           :: gr
    type(summary_col_t), intent(inout) :: sc
    logical, intent(out)               :: cached

    ! Cache the item from resp_t data

    cached = .TRUE.

    select case (sc%item)

    $CACHE_VALUE(eul_Psi_ref,rs%eul_Psi(rs%j_ref))
    $CACHE_VALUE(Phi_T_ref,rs%Phi_T(rs%j_ref))
    $CACHE_VALUE(k,rs%k)
    $CACHE_VALUE(Omega_orb, rs%Omega_orb(ot_p%freq_units, ot_p%freq_frame))
    $CACHE_VALUE(q, rs%or_p%q)
    $CACHE_VALUE(e, rs%or_p%e)
    $CACHE_VALUE(R_a, rs%R_a())
    $CACHE_VALUE(cbar, rs%cbar())
    $CACHE_VALUE(Gbar_1, rs%Gbar_1())
    $CACHE_VALUE(Gbar_2, rs%Gbar_2())
    $CACHE_VALUE(Gbar_3, rs%Gbar_3())
    $CACHE_VALUE(Gbar_4, rs%Gbar_4())

    case default

       cached = .FALSE.

    end select

    ! Finish

    return

  end subroutine cache_resp_

  !****

  subroutine cache_context_ (ot_p, cx, gr, j_ref, sc, cached)

    type(out_par_t), intent(in)        :: ot_p
    class(context_t), intent(in)       :: cx
    type(grid_t), intent(in)           :: gr
    integer, intent(in)                :: j_ref
    type(summary_col_t), intent(inout) :: sc
    logical, intent(out)               :: cached

    ! Cache the item from context_t data

    cached = .TRUE.

    select case (sc%item)

    $CACHE_VALUE(Omega_rot_ref,cx%Omega_rot(gr%pt(j_ref)))

    case default
       
       cached = .FALSE.

    end select

    ! Finish

    return

  end subroutine cache_context_

  !****

  subroutine cache_model_ (ot_p, ml, gr, l, sc, cached)

    type(out_par_t), intent(in)         :: ot_p
    class(model_t), pointer, intent(in) :: ml
    type(grid_t), intent(in)            :: gr
    integer, intent(in)                 :: l
    type(summary_col_t), intent(inout)  :: sc
    logical, intent(out)                :: cached

    ! Cache the item from model_t data

    cached = .TRUE.

    select case (sc%item)

    $CACHE_VALUE(Delta_p,ml%Delta_p(gr%x_i(), gr%x_o()))
    $CACHE_VALUE(Delta_g,ml%Delta_g(gr%x_i(), gr%x_o(), l*(l+1._WP)))

    case default
       
       select type (ml)

       class is (evol_model_t)

          call cache_evol_model_(ot_p, ml, gr, l, sc, cached)

       class default

          cached = .FALSE.

       end select

    end select

    ! Finish

    return

  end subroutine cache_model_

  !****

  subroutine cache_evol_model_ (ot_p, ml, gr, l, sc, cached)

    type(out_par_t), intent(in)              :: ot_p
    class(evol_model_t), pointer, intent(in) :: ml
    type(grid_t), intent(in)                 :: gr
    integer, intent(in)                      :: l
    type(summary_col_t), intent(inout)       :: sc
    logical, intent(out)                     :: cached

    ! Cache the item from evol_model_t data

    cached = .TRUE.

    select case (sc%item)
       
    $CACHE_VALUE(M_star,ml%M_star)
    $CACHE_VALUE(R_star,ml%R_star)
    $CACHE_VALUE(L_star,ml%L_star)

    case default

       cached = .FALSE.

    end select

    ! Finish

    return

  end subroutine cache_evol_model_

  !****

  $define $APPEND $sub

  $local $T $1
  $local $TYPE $2

  subroutine append_${T}_ (this, datum)

    class(summary_col_t), intent(inout) :: this
    $TYPE, intent(in)                   :: datum

    integer :: d

    ! Append the $TYPE datum to the column

    if (.NOT. ALLOCATED(this%data_$T)) then

       allocate(this%data_$T(D_0))

       this%data_$T(1) = datum

       this%type = TYPE_$T
       this%n = 1

    else

       $ASSERT(this%type == TYPE_$T,Cannot append to array)

       d = SIZE(this%data_$T)
       this%n = this%n + 1

       if (this%n > d) then
          d = 2*d
          call reallocate(this%data_$T, [d])
       endif

       this%data_$T(this%n) = datum

    end if
    
    ! Finish

    return

  end subroutine append_${T}_

  $endsub

  $APPEND(i,integer)
  $APPEND(r,real(WP))
  $APPEND(c,complex(WP))
  $APPEND(a,character(*))

end module gyre_summary
