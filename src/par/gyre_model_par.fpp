! Module   : gyre_model_par
! Purpose  : model parameters
!
! Copyright 2015-2020 Rich Townsend & The GYRE Team
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

module gyre_model_par

  ! Uses

  use core_kinds

  use gyre_constants

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  type :: model_par_t
     real(WP)                :: Gamma_1 = 5._WP/3._WP
     real(WP)                :: dx_snap = 0._WP
     real(WP)                :: x_i = 0._WP
     real(WP)                :: x_o = 1._WP
     real(WP)                :: s = 1._WP
     real(WP)                :: beta_m = 1._WP
     real(WP)                :: beta_p = 1._WP
     character(256)          :: model_type = 'HOM'
     character(256)          :: grid_type = 'UNI'
     character(256)          :: file_format = ''
     character(256)          :: data_format = ''
     character(256)          :: deriv_type = 'MONO'
     character(FILENAME_LEN) :: file = ''
     integer                 :: n = 10
     logical                 :: add_center = .TRUE.
     logical                 :: repair_As = .FALSE.
     logical                 :: force_linear = .FALSE.
  end type model_par_t
   
 ! Access specifiers

  private

  public :: model_par_t
  public :: read_model_par

  ! Procedures

contains

  subroutine read_model_par (unit, ml_p)

    integer, intent(in)            :: unit
    type(model_par_t), intent(out) :: ml_p

    integer                          :: n_ml_p
    real(WP)                         :: Gamma_1
    real(WP)                         :: dx_snap
    real(WP)                         :: x_i
    real(WP)                         :: x_o
    real(WP)                         :: s
    real(WP)                         :: beta_m
    real(WP)                         :: beta_p
    character(LEN(ml_p%model_type))  :: model_type
    character(LEN(ml_p%grid_type))   :: grid_type
    character(LEN(ml_p%file_format)) :: file_format
    character(LEN(ml_p%data_format)) :: data_format
    character(LEN(ml_p%deriv_type))  :: deriv_type
    character(LEN(ml_p%file))        :: file
    integer                          :: n
    logical                          :: add_center
    logical                          :: repair_As
    logical                          :: force_linear

    namelist /model/ Gamma_1, dx_snap, x_i, x_o, s, beta_m, beta_p, &
                     model_type, grid_type, file_format, data_format, deriv_type, &
                     file, n, add_center, repair_As, force_linear
    
    ! Count the number of model namelists

    rewind(unit)

    n_ml_p = 0

    count_loop : do
       read(unit, NML=model, END=100)
       n_ml_p = n_ml_p + 1
    end do count_loop

100 continue

    $ASSERT(n_ml_p == 1,Input file should contain exactly one &model namelist)

    ! Read model parameters

    rewind(unit)

    ! Set default values

    ml_p = model_par_t()

    Gamma_1 = ml_p%Gamma_1
    dx_snap = ml_p%dx_snap
    x_i = ml_p%x_i
    x_o = ml_p%x_o
    s = ml_p%s
    beta_m = ml_p%beta_m
    beta_p = ml_p%beta_p
    model_type = ml_p%model_type
    grid_type = ml_p%grid_type
    file_format = ml_p%file_format
    data_format = ml_p%data_format
    deriv_type = ml_p%deriv_type
    file = ml_p%file
    n = ml_p%n
    add_center = ml_p%add_center
    repair_As = ml_p%repair_As
    force_linear = ml_p%force_linear

    ! Read the namelist
    
    read(unit, NML=model)

    ! Store read values

    ml_p%Gamma_1 = Gamma_1
    ml_p%dx_snap = dx_snap
    ml_p%x_i = x_i
    ml_p%x_o = x_o
    ml_p%s = s
    ml_p%beta_m = beta_m
    ml_p%beta_p = beta_p
    ml_p%model_type = model_type
    ml_p%grid_type = grid_type
    ml_p%file_format = file_format
    ml_p%data_format = data_format
    ml_p%deriv_type = deriv_type
    ml_p%file = file
    ml_p%n = n
    ml_p%add_center = add_center
    ml_p%repair_As = repair_As
    ml_p%force_linear = force_linear

    ! Finish

    return

  end subroutine read_model_par

end module gyre_model_par
