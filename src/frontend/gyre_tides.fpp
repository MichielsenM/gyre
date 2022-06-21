! Program  : gyre_tides
! Purpose  : stellar tides code
!
! Copyright 2019-2022 Rich Townsend & The GYRE Team
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

program gyre_tides

  ! Uses

  use core_kinds, only : WP
  use core_hgroup
  use core_parallel
  use core_system

  use gyre_constants
  use gyre_detail
  use gyre_func
  use gyre_grid_par
  use gyre_math
  use gyre_model
  use gyre_model_factory
  use gyre_model_par
  use gyre_num_par
  use gyre_orbit_par
  use gyre_osc_par
  use gyre_out_par
  use gyre_resp
  use gyre_rot_par
  use gyre_search
  use gyre_summary
  use gyre_tide_par
  use gyre_tidal_resp
  use gyre_util
  use gyre_version

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Variables

  character(:), allocatable      :: filename
  integer                        :: unit
  type(model_par_t)              :: ml_p
  type(osc_par_t), allocatable   :: os_p(:)
  type(rot_par_t), allocatable   :: rt_p(:)
  type(num_par_t), allocatable   :: nm_p(:)
  type(grid_par_t), allocatable  :: gr_p(:)
  type(orbit_par_t), allocatable :: or_p(:)
  type(tide_par_t), allocatable  :: td_p(:)
  type(out_par_t)                :: ot_p
  class(model_t), pointer        :: ml => null()
  type(summary_t)                :: sm
  type(detail_t)                 :: dt
  integer                        :: i
  type(osc_par_t)                :: os_p_sel
  type(rot_par_t)                :: rt_p_sel
  type(num_par_t)                :: nm_p_sel
  type(grid_par_t)               :: gr_p_sel
  type(orbit_par_t)              :: or_p_sel

  ! Read command-line arguments

  $ASSERT(n_arg() == 1,Syntax: gyre_tide <filename>)

  call get_arg(1, filename)

  ! Initialize

  call init_parallel()
  call init_math()

  call set_log_level($str($LOG_LEVEL))

  if (check_log_level('INFO')) then

     write(OUTPUT_UNIT, 100) form_header('gyre_tides ['//VERSION//']', '-')
100  format(A)

     if (check_log_level('DEBUG')) then
        write(OUTPUT_UNIT, 110) 'Compiler         :', COMPILER_VERSION()
        write(OUTPUT_UNIT, 110) 'Compiler options :', COMPILER_OPTIONS()
110     format(A,1X,A)
     endif

     write(OUTPUT_UNIT, 120) 'OpenMP Threads   :', OMP_SIZE_MAX
120  format(A,1X,I0)
     
     write(OUTPUT_UNIT, 110) 'Input filename   :', filename

     write(OUTPUT_UNIT, *)

  endif

  ! Read the namelist file

  open(NEWUNIT=unit, FILE=filename, STATUS='OLD')

  call read_constants(unit)

  call read_constants(unit)

  call read_model_par(unit, ml_p)
  call read_osc_par(unit, os_p)
  call read_rot_par(unit, rt_p)
  call read_num_par(unit, nm_p)
  call read_grid_par(unit, gr_p)
  call read_orbit_par(unit, or_p)
  call read_tide_par(unit, td_p)
  call read_out_par(unit, 'tides', ot_p)

  close(unit)

  ! Check that GYRE_DIR is set

  $ASSERT(GYRE_DIR /= '',The GYRE_DIR environment variable is not set)

  ! Initialize the model

  if (check_log_level('INFO')) then
     write(OUTPUT_UNIT, 100) form_header('Model Init', '-')
  endif

  ml => model_t(ml_p)

  ! Initialize the summary and detail outputters

  sm = summary_t(ot_p)

  dt = detail_t(ot_p)

  ! Loop through td_p

  td_p_loop : do i = 1, SIZE(td_p)

     if (check_log_level('INFO')) then

        write(OUTPUT_UNIT, 100) form_header('Response Evaluation', '-')

        write(OUTPUT_UNIT, 100) 'Expansion parameters'

        write(OUTPUT_UNIT, 130) 'l_[min,max] :', td_p(i)%l_min, td_p(i)%l_max
        write(OUTPUT_UNIT, 130) 'm_[min,max] :', MAX(-td_p(i)%l_max, td_p(i)%m_min), MIN(td_p(i)%l_max, td_p(i)%m_max)
        write(OUTPUT_UNIT, 130) 'k_[min,max] :', td_p(i)%k_min, td_p(i)%k_max
130     format(3X,A,1X,I0,1X,I0)

        write(OUTPUT_UNIT, *)

     endif

     ! Select parameters according to tags

     call select_par(os_p, td_p(i)%tag, os_p_sel)
     call select_par(rt_p, td_p(i)%tag, rt_p_sel)
     call select_par(nm_p, td_p(i)%tag, nm_p_sel)
     call select_par(gr_p, td_p(i)%tag, gr_p_sel)
     call select_par(or_p, td_p(i)%tag, or_p_sel)

     ! Solve for the partial tidal responses

     call eval_resp(ml, process_resp, gr_p_sel, nm_p_sel, or_p_sel, os_p_sel, rt_p_sel, td_p(i))

  end do td_p_loop

  ! Write the summary

  call sm%write()

  ! Clean up

  deallocate(ml)

  ! Finish

  call final_parallel()

contains

  subroutine process_resp (rs)

     type(resp_t), intent(in) :: rs

     ! Cache/write the tidal response

     call sm%cache(rs)
     call dt%write(rs)

     ! Finish

     return

  end subroutine process_resp

end program gyre_tides
