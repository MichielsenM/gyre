.. _output-params:

Output Parameters
=================

The :nml_g:`ad_output`, :nml_g:`nad_output` and :nml_g:`tides_output`
namelist groups determine the output produced at the end of a run (the
first two for the adiabatic and non-adiabatic calculation stages of
:program:`gyre`; the third for :program:`gyre_tides`). Parameters are
as follows:

:nml_n:`summary_file` (default :nml_v:`''`)
  Name of summary file

:nml_n:`summary_file_format` (default :nml_v:`'HDF'`)
  Format of summary file; one of

  - :nml_v:`'HDF'` : HDF5 file
  - :nml_v:`'TXT'` : Text file

:nml_n:`summary_item_list` (default :nml_v:`'l,n_pg,omega,freq'`)
  Comma-separated list of output items to write to summary file; see the
  :ref:`summary-files` section for possible choices

:nml_n:`summary_filter_list` (default :nml_v:`''`)
  Comma-separated list of filter criteria for summary files; see the
  :ref:`output-filters` section for possible choices

:nml_n:`detail_template` (default :nml_v:`''`)
  Name template of detail files. Names are generated using the following pattern
  substitutions:

  - :nml_v:`'%ID'` : Unique mode index, formatted in fixed-width field
  - :nml_v:`'%id'` : Same as :nml_v:`'%ID'`, but formatted in variable-width field
  - :nml_v:`'%L'` : Harmonic degree :math:`\ell`, formatted in fixed-width field
  - :nml_v:`'%l'` : Same as :nml_v:`'%L'`, but formatted in variable-width field
  - :nml_v:`'%M'` : Azimuthal order :math:`m`, formatted in fixed-width field
  - :nml_v:`'%m'` : Same as :nml_v:`'%M'`, but formatted in variable-width field
  - :nml_v:`'%N'` : Radial order :math:`n_{\rm pg}`, formatted in fixed-width field
  - :nml_v:`'%n'` : Same as :nml_v:`'%N'`, but formatted in variable-width field
  - :nml_v:`'%P'` : Acoustic wave winding number :math:`n_{\rm p}`, formatted in fixed-width field
  - :nml_v:`'%p'` : Same as :nml_v:`'%P'`, but formatted in variable-width field
  - :nml_v:`'%G'` : Gravity wave winding number :math:`n_{\rm g}`, formatted in fixed-width field
  - :nml_v:`'%g'` : Same as :nml_v:`'%G'`, but formatted in variable-width field

:nml_n:`detail_file_format` (default :nml_v:`'HDF'`)
  Format of detail files; one of

  - :nml_n:`'HDF'` : HDF5 file
  - :nml_v:`'TXT'` : text file

:nml_n:`detail_item_list` (default :nml_v:`'l,n_pg,omega,freq,x,xi_r,xi_h'`)
  Comma-separated list of output items to write to detail files; see the
  :ref:`detail-files` section for possible choices

:nml_n:`detail_filter_list` (default :nml_v:`''`)
  Comma-separated list of filter criteria for detail files; see the
  :ref:`output-filters` section for possible choices

:nml_n:`freq_units` (default :nml_v:`NONE`)
  Units of :nml_v:`freq` output item; one of:

  - :nml_v:`'NONE'` : Dimensionless angular frequency
  - :nml_v:`'HZ'` : linear frequency in Hz\ [#only-D]_
  - :nml_v:`'UHZ'` : linear frequency in μHz\ [#only-D]_
  - :nml_v:`'RAD_PER_SEC'` : angular frequency in radians per second\ [#only-D]_
  - :nml_v:`'CYC_PER_DAY'` : linear frequency in cycles per day\ [#only-D]_
  - :nml_v:`'ACOUSTIC_DELTA'` : Fraction of the asymptotic acoustic large frequency separation :math:`\Delta \nu`
  - :nml_v:`'GRAVITY_DELTA'` : Fraction of the asymptotic inverse gravity period separation :math:`(\Delta P)^{-1}`
  - :nml_v:`'UPPER_DELTA'` : Greater of :math:`\Delta \nu` and :math:`(\Delta P)^{-1}`
  - :nml_v:`'LOWER_DELTA'` : Lesser of :math:`\Delta \nu` and :math:`(\Delta P)^{-1}`
  - :nml_v:`'ACOUSTIC_CUTOFF'` : fraction of the acoustic cutoff frequency\ [#only-D]_
  - :nml_v:`'GRAVITY_CUTOFF'` : fraction of the gravity cutoff frequency\ [#only-D]_
  - :nml_v:`'ROSSBY_I'` : fraction of Rossby frequency at inner boundary
  - :nml_v:`'ROSSBY_O'` : fraction of Rossby frequency at outer boundary

:nml_n:`freq_frame` (default :nml_v:`INERTIAL`)
  Frame of :nml_v:`freq` output item; one of:

   - :nml_v:`'INERTIAL'` : Inertial frame
   - :nml_v:`'COROT_I'` : Co-rotating frame at inner boundary
   - :nml_v:`'COROT_O'` : Co-rotating frame at outer boundary

:nml_n:`label` (default :nml_v:`''`)
  Textual label to add to all output files

.. rubric:: Footnotes

.. [#only-D] This option is available only for stellar models with :ref:`D capability <model-caps>`
