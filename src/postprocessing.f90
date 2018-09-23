!-------------------------------------------------------------------------------
! Wrapper for different postprocessing tools
!-------------------------------------------------------------------------------
subroutine postprocessing()
  use vars
  use mpi
  implicit none
  character(len=strlen) :: postprocessing_mode, filename, key1,key2, mode
  logical :: help
  real(kind=pr) :: t1
  help = .false.
  t1=MPI_wtime()

  ! the first argument is either "-p" or "-h"
  call get_command_argument(1,mode)

  ! the second argument tells us what to do
  call get_command_argument(2,postprocessing_mode)

  ! if mode is help, then we'll call the routines with help=.true. and skip
  ! all other output
  if ((mode=="-h").or.(mode=="--help")) then
    ! we'll just show the help for the routine (we even skip the header)
    help=.true.
  else
    ! we'll actually do something, postprocessing
    if (mpirank==0) then
      write(*,'(80("~"))')
      write(*,'(A)') "~~~ FLUSI is running in postprocessing mode"
      write(*,'(80("~"))')
    endif
    ! show the call from the command line in output
    call postprocessing_ascii_header( 6 )
  endif

  !-----------------
  ! check what to do
  !-----------------
  select case (postprocessing_mode)
  case ("--simple-field-operation")
    call simple_field_operation(help)
  case ("--cp")
    call copy_hdf_file(help)
  case ("--keyvalues")
    call get_command_argument(3,filename)
    call keyvalues (filename)
  case ("--compare-keys")
    call get_command_argument(3,key1)
    call get_command_argument(4,key2)
    call compare_key (key1,key2)
  case ("--compare-timeseries")
    call compare_timeseries(help)
  case ("--vorticity","--vor")
    call convert_vorticity(help)
  case ("--vor2u")
    call convert_velocity(help)
  case ("--vor_abs","--vor-abs")
    call convert_abs_vorticity(help)
  case ("--hdf2bin")
    call convert_hdf2bin(help)
  case ("--bin2hdf")
    call convert_bin2hdf(help)
  case ("--p2Q")
    call pressure_to_Qcriterion(help)
  case ("--extract-subset")
    call extract_subset(help)
  case ("--time-avg")
    call time_avg_HDF5(help)
  case ("--upsample")
    call upsample(help)
  case ("--spectrum")
    call post_spectrum(help)
  case ("--turbulence-analysis")
    call turbulence_analysis(help)
  case ("--field-analysis")
    call field_analysis(help)
  case ("--TKE-mean")
    call tke_mean(help)
  case ("--max-over-x")
    call max_over_x(help)
  case ("--mean-over-x-subdomain")
    call mean_over_x_subdomain(help)
  case ("--mean-2D")
    call mean_2D(help)
  case ("--set-hdf5-attribute")
    call set_hdf5_attribute(help)
  case ("-ux-from-uyuz")
    call ux_from_uyuz(help)
  case ("--check-params-file")
    call check_params_file(help)
  case ("--magnitude")
    call magnitude_post(help)
  case ("--energy")
    call energy_post(help)
  case ("--helicity")
    call post_helicity(help)
  case ("--smooth-inverse-mask")
    call post_smooth_mask(help)
  case default
    if (root) then
      write(*,*) "Available Postprocessing tools are:"
      write(*,*) "--energy"
      write(*,*) "--magnitude"
      write(*,*) "--check-params-file"
      write(*,*) "--ux-from-uyuz"
      write(*,*) "--set-hdf5-attribute"
      write(*,*) "--mean-2D"
      write(*,*) "--mean-over-x-subdomain"
      write(*,*) "--max-over-x"
      write(*,*) "--TKE-mean"
      write(*,*) "--field-analysis"
      write(*,*) "--turbulence-analysis"
      write(*,*) "--spectrum"
      write(*,*) "--upsample"
      write(*,*) "--time-avg"
      write(*,*) "--extract-subset"
      write(*,*) "--p2Q"
      write(*,*) "--simple-field-operation"
      write(*,*) "--cp"
      write(*,*) "--keyvalues"
      write(*,*) "--compare-keys"
      write(*,*) "--compare-timeseries"
      write(*,*) "--vorticity  --vor"
      write(*,*) "--vor2u"
      write(*,*) "--vor_abs --vor-abs"
      write(*,*) "--hdf2bin"
      write(*,*) "--bin2hdf"
      write(*,*) "--helicity"
      write(*,*) "--smooth-inverse-mask"
      write(*,*) "Postprocessing option is "// trim(adjustl(postprocessing_mode))
      write(*,*) "But I don't know what to do with that"
  endif
  end select

  if ((mpirank==0).and.(help.eqv..false.)) then
    write(*,'("Elapsed time=",es12.4)') MPI_wtime()-t1
  endif
end subroutine postprocessing




!-------------------------------------------------------------------------------
! write the call to flusi (i.e. the command line arguments) to an ascii file
! use this in conjunction with small ascii output files to document a little
! bit what you have been doing.
!-------------------------------------------------------------------------------
subroutine postprocessing_ascii_header( io_stream )
  use vars
  implicit none
  integer, intent(in) :: io_stream
  integer :: i
  character(len=strlen) :: arg

  if (mpirank /= 0) return

  ! MATLAB comment character:
  write(io_stream,'(A,1x)',advance='no') "% CALL: ./flusi "

  arg = "-p"
  i=1
  ! loop over command line arguments and dump them to the file:
  do while ( arg /= "" )
    call get_command_argument(i,arg)
    write(io_stream,'(A,1x)',advance='no') trim(adjustl(arg))
    i=i+1
  end do

  write(io_stream,'(A,1x)',advance='yes') "%"
end subroutine postprocessing_ascii_header





!-------------------------------------------------------------------------------
! ./flusi --postprocess --hdf2bin ux_00000.h5 filename.bin
!-------------------------------------------------------------------------------
! converts the *.h5 file to an ordinairy binary file
subroutine convert_hdf2bin(help)
  use vars
  use mpi
  use basic_operators
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname, fname_bin
  real(kind=pr), dimension(:,:,:), allocatable :: field
  integer, parameter :: pr_out = 4
  integer :: ix, iy ,iz
  real(kind=pr_out), dimension(:,:,:), allocatable :: field_out ! single precision
  real(kind=pr) :: time


  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --hdf2bin ux_00000.h5 filename.bin"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "convert the given HDF5 file to a FORTRAN binary file"
    write(*,*) "Ordering:"
    write(*,*) "write (12) (((field_out (ix,iy,iz), ix=0, nx-1), iy=0, ny-1), iz=0, nz-1)"
    write(*,*) "SINGLE PRECISION, LITTLE_ENDIAN"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: NO"
    return
  endif


  call get_command_argument(3,fname)
  call get_command_argument(4,fname_bin)

  ! check if input file exists
  call check_file_exists ( fname )

  if ( mpisize>1 ) then
    write (*,*) "--hdf2bin is currently a serial version only, run it on 1CPU"
    return
  endif

  call fetch_attributes( fname, nx, ny, nz, xl, yl, zl, time, nu )

  write (*,'("Converting ",A," to ",A," Resolution is",3(i4,1x))') &
  trim(fname), trim(fname_bin), nx,ny,nz
  write (*,'("time=",es12.4," xl=",es12.4," yl=",es12.4," zl=",es12.4)') &
  time, xl, yl, zl

  ra=(/0,0,0/)
  rb=(/nx-1,ny-1,nz-1/)
  allocate ( field(0:nx-1,0:ny-1,0:nz-1),field_out(0:nx-1,0:ny-1,0:nz-1) )

  ! read field from hdf file
  call read_single_file (fname, field)

  ! convert to single precision
  field_out = real(field, kind=pr_out)

  write (*,'("maxval=",es12.4," minval=",es12.4)') maxval(field_out),minval(field_out)

  ! dump binary file (this file will be called ux_00100.h5.binary)
  open (12, file = trim(fname_bin), form='unformatted', status='replace',&
  convert="little_endian")
  write (12) (((field_out (ix,iy,iz), ix=0, nx-1), iy=0, ny-1), iz=0, nz-1)
  !  write(12) field_out
  close (12)

  deallocate (field, field_out)
end subroutine convert_hdf2bin



!-------------------------------------------------------------------------------
! ./flusi --postprocess --time-avg file_list.txt avgx_0000.h5
! Reads in a list of files from a file, then loads one file after the other and
! computes the average field, which is then stored in the specified file.
!-------------------------------------------------------------------------------
subroutine time_avg_HDF5(help)
  use vars
  use mpi
  use basic_operators
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname, fname_bin, fname_avg
  real(kind=pr), dimension(:,:,:), allocatable :: field_avg, field
  integer :: ix, iy ,iz, io_error=0, i=0
  real(kind=pr) :: time

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --time-avg file_list.txt avgx_0000.h5"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) " Reads in a list of files from a file, then loads one file after the other and"
    write(*,*) " computes the average field, which is then stored in the specified file."
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: NO"
    return
  endif


  call get_command_argument(3,fname)
  call get_command_argument(4,fname_avg)

  !-----------------------------------------------------------------------------
  ! check if input file exists, the file contains the list of h5 files to be avg
  !-----------------------------------------------------------------------------
  call check_file_exists ( fname )
  write(*,*) "Reading list of files from "//fname

  if ( mpisize>1 ) then
    write (*,*) "--time-avg is currently a serial version only, run it on 1CPU"
    return
  endif

  !-----------------------------------------------------------------------------
  ! read in the file, loop over lines
  !-----------------------------------------------------------------------------
  open( unit=14,file=fname, action='read', status='old')
  do while (io_error==0)
    ! fetch current filename
    read (14,'(A)', iostat=io_error) fname_bin
    write(*,*) "read "//trim(adjustl(fname_bin))
    if (io_error == 0) then
      write(*,*) "Processing file "//trim(adjustl(fname_bin))

      call check_file_exists ( fname_bin )
      call fetch_attributes( fname_bin, nx, ny, nz, &
      xl, yl, zl, time, nu )

      ! first time? allocate then.
      if ( .not. allocated(field_avg) ) then
        ra=(/0,0,0/)
        rb=(/nx-1,ny-1,nz-1/)
        allocate(field_avg(0:nx-1,0:ny-1,0:nz-1))
        allocate(field(0:nx-1,0:ny-1,0:nz-1))
        field_avg = 0.d0
      endif

      ! read the field from file
      call read_single_file( fname_bin, field )

      field_avg = field_avg + field

      i = i+1
    endif
  enddo
  close (14)

  field_avg = field_avg / dble(i)

  call save_field_hdf5(0.d0, fname_avg, field_avg)

  deallocate(field_avg)
  deallocate(field)


end subroutine time_avg_HDF5



!-------------------------------------------------------------------------------
! ./flusi --postprocess --bin2hdf [file_bin] [file_hdf5] [nx] [ny] [nz] [xl] [yl] [zl] [time]
! ./flusi --postprocess --bin2hdf ux_file.binary ux_00000.h5 128 128 384 3.5 2.5 10.0 0.0
!-------------------------------------------------------------------------------
! converts the given binary file into an HDF5 file following flusi's conventions
subroutine convert_bin2hdf(help)
  use vars
  use mpi
  use basic_operators
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_bin,fname_hdf,tmp
  real, dimension(:,:,:), allocatable :: field
  integer, parameter :: pr_out = 4
  integer :: ix, iy ,iz, i,j,k
  integer(kind=8) :: record_length
  real(kind=pr) :: time

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --bin2hdf [file_bin] [file_hdf5] [nx] [ny] [nz] [xl] [yl] [zl] [time]"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "converts the given binary file into an HDF5 file following flusi's conventions"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: Nope"
    return
  endif


  if ( mpisize>1 ) then
    write (*,*) "--hdf2bin is currently a serial version only, run it on 1CPU"
    return
  endif


  ! binary file name
  call get_command_argument(3,fname_bin)
  ! hdf5 file name
  call get_command_argument(4,fname_hdf)
  call get_command_argument(5,tmp)
  read (tmp,*) nx
  call get_command_argument(6,tmp)
  read (tmp,*) ny
  call get_command_argument(7,tmp)
  read (tmp,*) nz
  call get_command_argument(8,tmp)
  read (tmp,*) xl
  call get_command_argument(9,tmp)
  read (tmp,*) yl
  call get_command_argument(10,tmp)
  read (tmp,*) zl
  call get_command_argument(11,tmp)
  read (tmp,*) time

  write(*,'("converting ",A," into ",A," resolution: ",3(i4,1x)," box size: ",&
  &3(es15.8,1x)," time=",es15.8)') trim(adjustl(fname_bin)), &
  trim(adjustl(fname_hdf)), nx,ny,nz, xl,yl,zl,time

  !-----------------------------------------------------------------------------
  ! read in the binary field to be converted
  !-----------------------------------------------------------------------------
  allocate ( field(0:nx-1,0:ny-1,0:nz-1) )

  !   inquire (iolength=record_length) field
  !   open(11, file=fname_bin, form='unformatted', &
  !   access='direct', recl=record_length, convert="little_endian")
  !   read (11,rec=1) field
  !   close (11)
  !   write (*,'("maxval=",es12.4," minval=",es12.4)') maxval(field),minval(field)


  OPEN(10,FILE=fname_bin,FORM='unformatted',STATUS='OLD', convert='LITTLE_ENDIAN')
  read(10) (((field(i,j,k),i=0,nx-1),j=0,ny-1),k=0,nz-1)
  CLOSE(10)
  write (*,'("maxval=",es12.4," minval=",es12.4)') maxval(field),minval(field)
  !-----------------------------------------------------------------------------
  ! write the field data to an HDF file
  !-----------------------------------------------------------------------------
  ! initializes serial domain decomposition:
  ra=(/0, 0, 0/)
  rb=(/nx-1, ny-1, nz-1/)

  call save_field_hdf5(time,fname_hdf,dble(field))

  deallocate (field)
end subroutine convert_bin2hdf




!-------------------------------------------------------------------------------
! ./flusi --postprocess --vor_abs ux_00000.h5 uy_00000.h5 uz_00000.h5 --second-order
!-------------------------------------------------------------------------------
! load the velocity components from file and compute & save the vorticity
! directly compute the absolute value of vorticity, do not save components
! can be done in parallel
subroutine convert_abs_vorticity(help)
  use vars
  use p3dfft_wrapper
  use mpi
  use helpers
  use basic_operators
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, order
  complex(kind=pr),dimension(:,:,:,:),allocatable :: uk
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr) :: time

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --vor-abs ux_00000.h5 uy_00000.h5 uz_00000.h5 [--second-order]"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) " load the velocity components from file and compute & save the vorticity"
    write(*,*) " directly compute the absolute value of vorticity, do not save components"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,order)

  call check_file_exists(fname_ux)
  call check_file_exists(fname_uy)
  call check_file_exists(fname_uz)

  if (mpirank == 0) then
    write(*,*) "Compute magnitude(vorticity) from velocity files:"
    write(*,*) "ux="//trim(adjustl(fname_ux))
    write(*,*) "uy="//trim(adjustl(fname_uy))
    write(*,*) "uz="//trim(adjustl(fname_uz))
    write(*,*) "order flag is: "//trim(adjustl(order))
  endif

  if ((fname_ux(1:2).ne."ux").or.(fname_uy(1:2).ne."uy").or.(fname_uz(1:2).ne."uz")) then
    write (*,*) "Error in arguments, files do not start with ux uy and uz"
    write (*,*) "note files have to be in the right order"
    call abort(9047)
  endif


  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  if (mpirank==0) write (*,*) "Done fft_initialize"

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))

  if (mpirank==0) write (*,*) "Allocated memory"

  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  call fft (uk(:,:,:,1),u(:,:,:,1))
  call fft (uk(:,:,:,2),u(:,:,:,2))
  call fft (uk(:,:,:,3),u(:,:,:,3))

  if (order=="--second-order") then
    if (mpirank==0) write(*,*) "using second order!"
    call curl_2nd(uk(:,:,:,1),uk(:,:,:,2),uk(:,:,:,3))
  else
    if (mpirank==0) write(*,*) "using spectral accuracy!"
    call curl(uk(:,:,:,1),uk(:,:,:,2),uk(:,:,:,3))
  endif

  call ifft (u(:,:,:,1),uk(:,:,:,1))
  call ifft (u(:,:,:,2),uk(:,:,:,2))
  call ifft (u(:,:,:,3),uk(:,:,:,3))

  ! now u contains the mag(vorticity) in physical space
  fname_ux='vorabs'//fname_ux(index(fname_ux,'_'):index(fname_ux,'.')-1)

  if (mpirank == 0) then
    write (*,'("Writing mag(vor) to file: ",A)') trim(fname_ux)
  endif

  ! compute absolute vorticity:
  u(:,:,:,1) = dsqrt(u(:,:,:,1)**2 + u(:,:,:,2)**2 + u(:,:,:,3)**2)

  call save_field_hdf5 ( time,fname_ux,u(:,:,:,1))

  deallocate (u)
  deallocate (uk)
  call fft_free()

end subroutine convert_abs_vorticity



!-------------------------------------------------------------------------------
! Read velocity components from file and compute their curl. Optionally second order
!
! You can write to standard output: (vorx_0000.h5 in the example:)
! ./flusi -p --vorticity ux_00000.h5 uy_00000.h5 uz_00000.h5 [--second-order]
!
! Or specify a prefix for the output files: (writes to curl_0000.h5 in example:)
! ./flusi -p --vorticity ux_00000.h5 uy_00000.h5 uz_00000.h5 --outputprefix curl [--second-order]
!
! Or specifiy the ouput files directly:
! ./flusi -p --vorticity ux_00000.h5 uy_00000.h5 uz_00000.h5 --outfiles vx_00.h5 vy_00.h5 vz_00.h5 [--second-order]
!
!-------------------------------------------------------------------------------
! load the velocity components from file and compute & save the vorticity
! can be done in parallel. the flag --second order can be used for filtering
subroutine convert_vorticity(help)
  use vars
  use p3dfft_wrapper
  use helpers
  use basic_operators
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, order
  character(len=strlen) :: prefix, fname_outx, fname_outy, fname_outz
  complex(kind=pr),dimension(:,:,:,:),allocatable :: uk
  complex(kind=pr),dimension(:,:,:),allocatable :: workc
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr),dimension(:,:,:),allocatable :: workr
  real(kind=pr) :: time, divu_max

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) " Read velocity components from file and compute their curl. Optionally second order"
    write(*,*) " "
    write(*,*) " You can write to standard output: (vorx_0000.h5 in the example:)"
    write(*,*) " ./flusi -p --vorticity ux_00000.h5 uy_00000.h5 uz_00000.h5 [--second-order]"
    write(*,*) " "
    write(*,*) " Or specify a prefix for the output files: (writes to curl_0000.h5 in example:)"
    write(*,*) " ./flusi -p --vorticity ux_00000.h5 uy_00000.h5 uz_00000.h5 --outputprefix curl [--second-order]"
    write(*,*) " "
    write(*,*) " Or specifiy the ouput files directly:"
    write(*,*) " ./flusi -p --vorticity ux_00000.h5 uy_00000.h5 uz_00000.h5 --outfiles vx_00.h5 vy_00.h5 vz_00.h5 [--second-order]"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,order)

  if (order == "--outputprefix") then
    call get_command_argument(7,prefix)
    call get_command_argument(8,order)
    fname_outx=trim(adjustl(prefix))//"x"//fname_ux(index(fname_ux,'_'):index(fname_ux,'.')-1)
    fname_outy=trim(adjustl(prefix))//"y"//fname_uy(index(fname_uy,'_'):index(fname_uy,'.')-1)
    fname_outz=trim(adjustl(prefix))//"z"//fname_uz(index(fname_uz,'_'):index(fname_uz,'.')-1)

  elseif (order == "--outfiles") then
    call get_command_argument(7,fname_outx)
    call get_command_argument(8,fname_outy)
    call get_command_argument(9,fname_outz)
    call get_command_argument(10,order)

  else
    fname_outx='vorx'//fname_ux(index(fname_ux,'_'):index(fname_ux,'.')-1)
    fname_outy='vory'//fname_uy(index(fname_uy,'_'):index(fname_uy,'.')-1)
    fname_outz='vorz'//fname_uz(index(fname_uz,'_'):index(fname_uz,'.')-1)
  endif

  ! header and information
  if (mpirank==0) then
    write(*,'(80("-"))')
    write(*,*) "vor2u (Biot-Savart)"
    write(*,*) "Computing vorticity from velocity given in these files: "
    write(*,'(80("-"))')
    write(*,*) trim(adjustl(fname_ux))
    write(*,*) trim(adjustl(fname_uy))
    write(*,*) trim(adjustl(fname_uz))
    write(*,*) "Writing to:"
    write(*,*) trim(adjustl(fname_outx))
    write(*,*) trim(adjustl(fname_outy))
    write(*,*) trim(adjustl(fname_outz))
    write(*,*) "Using order flag: "//trim(adjustl(order))
    write(*,'(80("-"))')
    if ((fname_ux(1:2).ne."ux").or.(fname_uy(1:2).ne."uy").or.(fname_uz(1:2).ne."uz")) then
      write (*,*) "WARNING! in arguments, files do not start with ux uy and uz"
      write (*,*) "note files have to be in the right order"
    endif
  endif

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))

  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  ! to Fourier space
  call fft3 (inx=u, outk=uk)

  !-----------------------------------------------------------------------------
  ! compute divergence of input fields and show the maximum value
  !-----------------------------------------------------------------------------
  allocate( workr(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)) )
  allocate( workc(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3)) )
  call divergence( uk, workc)
  call ifft( ink=workc, outx=workr )
  divu_max = fieldmax(workr)
  if(mpirank==0) write(*,'("maximum divergence in input field=",es12.4)') divu_max
  deallocate(workr,workc)

  !-----------------------------------------------------------------------------
  ! compute curl, possibly with second order filter
  !-----------------------------------------------------------------------------
  if (order=="--second-order") then
    if (mpirank==0) write(*,*) "using SECOND ORDER accuracy"
    call curl_2nd(uk(:,:,:,1),uk(:,:,:,2),uk(:,:,:,3))
  else
    if (mpirank==0) write(*,*) "using SPECTRAL accuracy"
    call curl(uk(:,:,:,1),uk(:,:,:,2),uk(:,:,:,3))
  endif

  call ifft3 (ink=uk, outx=u)

  ! now u contains the vorticity in physical space
  call save_field_hdf5 ( time,fname_outx,u(:,:,:,1) )
  call save_field_hdf5 ( time,fname_outy,u(:,:,:,2) )
  call save_field_hdf5 ( time,fname_outz,u(:,:,:,3) )

  deallocate (u)
  deallocate (uk)
  call fft_free()

end subroutine convert_vorticity



!-------------------------------------------------------------------------------
! Read in vorticity fields and compute the corresponding velocity (Biot-Savart Law)
! Some checks are performed on the result, namely divergence(u) and we see
! if the curl(result) is the same as the input values.
!
! you can optionally specify the list of outfiles:
! ./flusi -p --vor2u vorx_00.h5 vory_00.h5 vorz_00.h5 --outfiles outx_00.h5 outy_00.h5 outz_00.h5
!
! or write to the default file names: (ux_00.h5 in the example)
! ./flusi -p --vor2u vorx_00.h5 vory_00.h5 vorz_00.h5
!
! or specify the basename prefix: (writes to outx_00.h5 in the example:)
! ./flusi -p --vor2u vorx_00.h5 vory_00.h5 vorz_00.h5 --outputprefix out
!
!-------------------------------------------------------------------------------
subroutine convert_velocity(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use helpers
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, outfiles_given
  character(len=strlen) :: fname_outx, fname_outy, fname_outz, prefix
  complex(kind=pr),dimension(:,:,:,:),allocatable :: uk, workc
  real(kind=pr),dimension(:,:,:,:),allocatable :: u,workr
  real(kind=pr) :: time, divu_max, errx, erry, errz
  integer :: ix,iy,iz, mpicode

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --vor2u"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! Read in vorticity fields and compute the corresponding velocity (Biot-Savart Law)"
    write(*,*) "! Some checks are performed on the result, namely divergence(u) and we see"
    write(*,*) "! if the curl(result) is the same as the input values."
    write(*,*) "!"
    write(*,*) "! you can optionally specify the list of outfiles:"
    write(*,*) "! ./flusi -p --vor2u vorx_00.h5 vory_00.h5 vorz_00.h5 --outfiles outx_00.h5 outy_00.h5 outz_00.h5"
    write(*,*) "!"
    write(*,*) "! or write to the default file names: (ux_00.h5 in the example)"
    write(*,*) "! ./flusi -p --vor2u vorx_00.h5 vory_00.h5 vorz_00.h5"
    write(*,*) "!"
    write(*,*) "! or specify the basename prefix: (writes to outx_00.h5 in the example:)"
    write(*,*) "! ./flusi -p --vor2u vorx_00.h5 vory_00.h5 vorz_00.h5 --outputprefix out"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  !-----------------------------------------------------------------------------
  ! Initializations
  !-----------------------------------------------------------------------------
  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,outfiles_given)

  if ( outfiles_given == "--outfiles" ) then
    call get_command_argument(7,fname_outx)
    call get_command_argument(8,fname_outy)
    call get_command_argument(9,fname_outz)
  elseif ( outfiles_given == "--outputprefix" ) then
    ! if not specified, use standard output names:
    call get_command_argument(7,prefix)
    fname_outx=trim(adjustl(prefix))//"x"//fname_ux(index(fname_ux,'_'):index(fname_ux,'.')-1)
    fname_outy=trim(adjustl(prefix))//"y"//fname_uy(index(fname_uy,'_'):index(fname_uy,'.')-1)
    fname_outz=trim(adjustl(prefix))//"z"//fname_uz(index(fname_uz,'_'):index(fname_uz,'.')-1)
  else
    ! if not specified, use standard output names:
    fname_outx='ux'//fname_ux(index(fname_ux,'_'):index(fname_ux,'.')-1)
    fname_outy='uy'//fname_uy(index(fname_uy,'_'):index(fname_uy,'.')-1)
    fname_outz='uz'//fname_uz(index(fname_uz,'_'):index(fname_uz,'.')-1)
  endif

  ! header and information
  if (mpirank==0) then
    write(*,'(80("-"))')
    write(*,*) "vor2u (Biot-Savart)"
    write(*,*) "Computing velocity from vorticity given in these files: "
    write(*,'(80("-"))')
    write(*,*) trim(adjustl(fname_ux))
    write(*,*) trim(adjustl(fname_uy))
    write(*,*) trim(adjustl(fname_uz))
    write(*,*) "Writing to:"
    write(*,*) trim(adjustl(fname_outx))
    write(*,*) trim(adjustl(fname_outy))
    write(*,*) trim(adjustl(fname_outz))
    write(*,'(80("-"))')
    if ((fname_ux(1:4).ne."vorx").or.(fname_uy(1:4).ne."vory").or.(fname_uz(1:4).ne."vorz")) then
      write (*,*) "WARNING in arguments, files do not start with vorx vory and vorz"
      write (*,*) "note files have to be in the right order"
    endif
  endif

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi = 4.d0 *datan(1.d0)
  scalex = 2.d0*pi/xl
  scaley = 2.d0*pi/yl
  scalez = 2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)
  neq=3
  nd=3
  ncw=3
  nrw=3

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(workr(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))
  allocate(workc(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))

  ! read vorticity from files to u
  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  ! compute divergence of input fields and show the maximum value, this is interesting
  ! to know since actually, div(curl(u)) should be identically zero. however, in
  ! a discrete setting, this may not strictly be the case
  call fft3( inx=u,outk=uk ) ! uk is now vork
  call divergence( uk, workc(:,:,:,1) )
  call ifft( ink=workc(:,:,:,1), outx=workr(:,:,:,1) )
  divu_max = fieldmax(workr(:,:,:,1))
  if(mpirank==0) write(*,'("maximum divergence in input field=",es12.4)') divu_max

  ! copy original vorticity to workr (for comparison later, error checks)
  workr = u

  !-----------------------------------------------------------------------------
  ! compute velocity from vorticity
  !-----------------------------------------------------------------------------
  ! uk: vorticity; workc: velocity
  call Vorticity2Velocity(uk,workc)
  call ifft3 (ink=workc, outx=u)
  uk = workc ! uk: velocity in F-space

  ! now u contains the velocity in physical space
  call save_field_hdf5 ( time,fname_outx,u(:,:,:,1) )
  call save_field_hdf5 ( time,fname_outy,u(:,:,:,2) )
  call save_field_hdf5 ( time,fname_outz,u(:,:,:,3) )

  if (mpirank==0) then
    write(*,*) "Done writing output!"
    write(*,'(80("-"))')
    write(*,*) "Done computing, performing some analysis of the result..."
  endif

  !-----------------------------------------------------------------------------
  ! check divergence of new field
  !-----------------------------------------------------------------------------
  call divergence(uk,workc(:,:,:,1))
  call ifft(ink=workc(:,:,:,1),outx=u(:,:,:,1))
  divu_max = fieldmax(u(:,:,:,1))
  if (mpirank==0) write(*,*) "max(div(u))", divu_max
  divu_max = fieldmin(u(:,:,:,1))
  if (mpirank==0) write(*,*) "min(div(u))", divu_max

  deallocate(workc)

  !-----------------------------------------------------------------------------
  ! check if the curl of computed velocity is the same as input values
  !-----------------------------------------------------------------------------
  call curl3_inplace(uk)
  call ifft3(ink=uk, outx=u)

  ! difference
  u(:,:,:,1)=u(:,:,:,1)-workr(:,:,:,1)
  u(:,:,:,2)=u(:,:,:,2)-workr(:,:,:,2)
  u(:,:,:,3)=u(:,:,:,3)-workr(:,:,:,3)

  errx = fieldmax(u(:,:,:,1))
  erry = fieldmax(u(:,:,:,2))
  errz = fieldmax(u(:,:,:,3))

  if (mpirank==0) then
    write(*,*) "max diff vor_original-curl(result)", errx
    write(*,*) "max diff vor_original-curl(result)", erry
    write(*,*) "max diff vor_original-curl(result)", errz
  endif

  ! check relative difference in mag(vor):
  errx=0.d0
  erry=0.d0
  do iz=ra(3),rb(3)
    do iy=ra(2),rb(2)
      do ix=ra(1),rb(1)
        errx = errx + sqrt(u(ix,iy,iz,1)**2 + u(ix,iy,iz,2)**2 + u(ix,iy,iz,3)**2)
        erry = erry + sqrt(workr(ix,iy,iz,1)**2 + workr(ix,iy,iz,2)**2 + workr(ix,iy,iz,3)**2)
      enddo
    enddo
  enddo

  call MPI_ALLREDUCE (errx,errz,1,MPI_DOUBLE_PRECISION,MPI_MAX,MPI_COMM_WORLD,mpicode)
  call MPI_ALLREDUCE (erry,divu_max,1,MPI_DOUBLE_PRECISION,MPI_MAX,MPI_COMM_WORLD,mpicode)
  ! relative error:
  if (mpirank==0) write(*,*) "relative error in magnitude:", errz/divu_max

  deallocate (u)
  deallocate (uk)
  deallocate (workr)
  call fft_free()

end subroutine convert_velocity



!-------------------------------------------------------------------------------
! ./flusi --postprocess --keyvalues mask_00000.h5
!-------------------------------------------------------------------------------
! load the specified *.h5 file and creates a *.key file that contains
! min / max / mean / L2 norm of the field data. This is used for unit testing
! so that we don't need to store entire fields but rather the *.key only
subroutine keyvalues(filename)
  use vars
  use mpi
  implicit none
  character(len=*), intent(in) :: filename
  real(kind=pr) :: time, npoints, q, x,y,z
  real(kind=pr), dimension(:,:,:), allocatable :: field
  integer :: ix,iy,iz

  if (mpisize>1) then
    write (*,*) "--keyvalues is currently a serial version only, run it on 1CPU"
    call abort(7101)
  endif

  call check_file_exists( filename )

  write (*,*) "analyzing file "//trim(adjustl(filename))//" for keyvalues"

  !---------------------------------------------------------
  ! in a first step, we fetch the attributes from the dataset
  ! namely the resolution is whats important
  ! this routine was created in the mpi2vis repo -> convert_hdf2xmf.f90
  !---------------------------------------------------------
  call fetch_attributes( filename, nx, ny, nz, xl, yl, zl, time , nu )
  write(*,'("File is at time=",es12.4)') time
  allocate ( field(0:nx-1,0:ny-1,0:nz-1) )

  ra=(/0,0,0/)
  rb=(/nx-1,ny-1,nz-1/)
  call read_single_file (filename, field)

  npoints = dble(nx)*dble(ny)*dble(nz)

  ! compute an additional quantity that depends also on the position
  ! (the others are translation invariant)
  q=0.d0
  do iz = 0, nz-1
   do iy = 0, ny-1
    do ix = 0, nx-1
      x = dble(ix)*xl/dble(nx)
      y = dble(iy)*yl/dble(ny)
      z = dble(iz)*zl/dble(nz)

      q = q + x*field(ix,iy,iz) + y*field(ix,iy,iz) + z*field(ix,iy,iz)
      enddo
    enddo
  enddo

  open  (14, file = filename(1:index(filename,'.'))//'key', status = 'replace')
  write (14,'(6(es15.8,1x))') time, maxval(field), minval(field),&
   sum(field)/npoints, sum(field**2)/npoints, q/npoints
  write (*,'(6(es15.8,1x))') time, maxval(field), minval(field),&
   sum(field)/npoints, sum(field**2)/npoints, q/npoints
  close (14)

  deallocate (field)
end subroutine keyvalues





!-------------------------------------------------------------------------------
! ./flusi --postprocess --compare-timeseries forces.t ref/forces.t
!-------------------------------------------------------------------------------
subroutine compare_timeseries(help)
  use fsi_vars
  use mpi
  implicit none
  character(len=strlen) :: file1,file2
  character(len=1024) :: header, line
  character(len=15) ::format
  real(kind=pr),dimension(:),allocatable :: values1, values2, error
  real(kind=pr)::diff
  integer :: i,columns,io_error,columns2, mpicode
  logical, intent(in) :: help

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) ""
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,file1)
  call get_command_argument(4,file2)

  call check_file_exists(file1)
  call check_file_exists(file2)

  !-----------------------------------------------------------------------------
  ! how many colums are in the *.t file?
  !-----------------------------------------------------------------------------
  open  (14, file = file1, status = 'unknown', action='read')
  read (14,'(A)') header
  read (14,'(A)') line
  columns=1
  do i=2,len_trim(line)
    if ((line(i:i)==" ").and.(line(i+1:i+1)/=" ")) columns=columns+1
  enddo
  close (14)

  !-----------------------------------------------------------------------------
  ! how many colums are in the second *.t file?
  !-----------------------------------------------------------------------------
  open  (14, file = file1, status = 'unknown', action='read')
  read (14,'(A)') header
  read (14,'(A)') line
  columns2=1
  do i=2,len_trim(line)
    if ((line(i:i)==" ").and.(line(i+1:i+1)/=" ")) columns2=columns2+1
  enddo
  close (14)

  if(columns/=columns2) then
    write(*,*) "trying to compare two t files with different #columns..."
    call MPI_FINALIZE(mpicode)
    call exit(666)
  endif

  write(format,'("(",i2.2,"(es15.8,1x))")') columns
  !   write(*,*) format
  !-----------------------------------------------------------------------------
  ! alloc arrays, then scan line by line for errors
  !-----------------------------------------------------------------------------
  allocate( values1(1:columns), values2(1:columns), error(1:columns) )

  ! read in files, line by line
  io_error=0
  open (20, file = file1, status = 'unknown', action='read')
  open (30, file = file2, status = 'unknown', action='read')
  read (20,'(A)') header
  read (30,'(A)') header
  do while (io_error==0)
    ! compare this line
    read (20,*,iostat=io_error) values1
    read (30,*,iostat=io_error) values2

    do i=1,columns
      diff = values1(i)-values2(i)
      ! ignore values smaller 1e-4 in ref file
      if ((dabs(values2(i))>1.d-4).and.(diff>1.d-7)) then
        error(i) = dabs(diff/values2(i))
      else
        error(i) = 0.0
      endif
    enddo

    if (maxval(error)>1.d-4) then
      write(*,*) "time series comparison failed..."
      write(*,format) values1
      write(*,format) values2
      write(*,format) error
      call MPI_FINALIZE(mpicode)
      call exit(666)
    endif
  enddo
  close (20)
  close (30)
  deallocate (values1,values2,error)
end subroutine compare_timeseries

!-------------------------------------------------------------------------------
! ./flusi --postprocess --compare-keys mask_00000.key saved.key
!-------------------------------------------------------------------------------
! compares to *.key files if they're equal
subroutine compare_key(key1,key2)
  use vars
  use mpi
  implicit none
  character(len=*), intent(in) :: key1,key2
  real(kind=pr) :: a1,a2,b1,b2,c1,c2,d1,d2,t1,t2,q1,q2
  real(kind=pr) :: e1,e2,e3,e4,e0,e5
  integer ::mpicode

  call check_file_exists(key1)
  call check_file_exists(key2)

  open  (14, file = key1, status = 'unknown', action='read')
  read (14,'(6(es15.8,1x))') t1,a1,b1,c1,d1,q1
  close (14)

  open  (14, file = key2, status = 'unknown', action='read')
  read (14,'(6(es15.8,1x))') t2,a2,b2,c2,d2,q2
  close (14)

  write (*,'("present  : time=",es15.8," max=",es15.8," min=",es15.8," sum=",es15.8," sum**2=",es15.8," q=",es15.8)') &
  t1,a1,b1,c1,d1,q1

  write (*,'("reference: time=",es15.8," max=",es15.8," min=",es15.8," sum=",es15.8," sum**2=",es15.8," q=",es15.8)') &
  t2,a2,b2,c2,d2,q2

  ! errors:
  if (dabs(t2)>=1.0d-7) then
    e0 = dabs( (t2-t1) / t2 )
  else
    e0 = dabs( (t2-t1) )
  endif

  if (dabs(a2)>=1.0d-7) then
    e1 = dabs( (a2-a1) / a2 )
  else
    e1 = dabs( (a2-a1) )
  endif

  if (dabs(b2)>=1.0d-7) then
    e2 = dabs( (b2-b1) / b2 )
  else
    e2 = dabs( (b2-b1) )
  endif

  if (dabs(c2)>=1.0d-7) then
    e3 = dabs( (c2-c1) / c2 )
  else
    e3 = dabs( (c2-c1) )
  endif

  if (dabs(d2)>=1.0d-7) then
    e4 = dabs( (d2-d1) / d2 )
  else
    e4 = dabs( (d2-d1) )
  endif

  if (dabs(q2)>=1.0d-7) then
    e5 = dabs( (q2-q1) / q2 )
  else
    e5 = dabs( (q2-q1) )
  endif

  write (*,'("err(rel) : time=",es15.8," max=",es15.8," min=",es15.8," sum=",es15.8," sum**2=",es15.8," q=",es15.8)') &
  e0,e1,e2,e3,e4,e5

  if ((e1<1.d-4) .and. (e2<1.d-4) .and. (e3<1.d-4) .and. (e4<1.d-4) .and. (e0<1.d-4) .and. (e5<1.d-4)) then
    ! all cool
    write (*,*) "OKAY..."
    call MPI_FINALIZE(mpicode)
    call exit(0)
  else
    ! very bad
    write (*,*) "ERROR"
    call MPI_FINALIZE(mpicode)
    call exit(1)
  endif
end subroutine compare_key



!-------------------------------------------------------------------------------
! pressure_to_Qcriterion()
! converts a given pressure field and outputs the Q-criterion, computed with
! second order and periodic boundary conditions. Alternatively, one
! may use distint postprocessing tools, such as paraview, and compute the Q-crit
! there, but the accuracy may be different.
! note the precision is reduced to second order (by using the effective
! wavenumber), since spurious oscillations appear when computing it with
! spectral precision
!-------------------------------------------------------------------------------
! call:
! ./flusi --postprocess --p2Q p_00000.h5 Q_00000.h5
!-------------------------------------------------------------------------------
subroutine pressure_to_Qcriterion(help)
  use mpi
  use vars
  use basic_operators
  use p3dfft_wrapper
  implicit none
  character(len=strlen) :: fname_p, fname_Q
  complex(kind=pr),dimension(:,:,:),allocatable :: pk
  real(kind=pr),dimension(:,:,:),allocatable :: p
  real(kind=pr)::time,maxi,mini
  logical, intent(in) :: help

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) ""
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  ! get file to read pressure from and check if this is present
  call get_command_argument(3,fname_p)
  call check_file_exists( fname_p )
  ! get filename to save Q criterion to
  call get_command_argument(4,fname_Q)

  ! read in information from the file
  call fetch_attributes( fname_p, "p", nx, ny, nz, xl, yl, zl, time, nu )

  if (mpirank==0) then
    write(*,'("Computing Q criterion from  file ",A," saving to ",&
    & A," nx=",i4," ny=",i4," nz=",i4, &
    &"xl=",es12.4," yl=",es12.4," zl=",es12.4 )') &
    trim(fname_p), trim(fname_Q), nx,nx,nz,xl,yl,zl
  endif

  pi=4.d0 * datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl

  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate(p(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))
  allocate(pk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3)))

  call read_single_file(fname_p, p)
  call fft(inx=p, outk=pk)
  ! Q-criterion is 0.5*laplace(P)
  ! see http://books.google.de/books?id=FWmsrNv3BYoC&pg=PA23&lpg=PA23&dq=q-criterion&source=bl&ots=CW-1NPn9p0&sig=Zi_Z2iw-ZuDqJqYctM9OUrb5WMA&hl=de&sa=X&ei=ZBCXU9nHGInVPPTRgagO&ved=0CCgQ6AEwADgK#v=onepage&q=q-criterion&f=false
  call laplacien_inplace_filtered(pk)
  call ifft(ink=pk, outx=p)
  p=0.5d0*p

  call save_field_hdf5(time, fname_Q, p)

  maxi = fieldmax(P)
  mini = fieldmin(P)

  if (mpirank==0) then
    write(*,'("Q-criterion 2nd order maxval=",es12.4," minval=",es12.4)') maxi,mini
  endif

  deallocate(p,pk)
  call fft_free()
end subroutine pressure_to_Qcriterion


!-------------------------------------------------------------------------------
! extract subset
! loads a file to memory and extracts a subset, writing to a different file. We
! assume here that you do this for visualization; in this case, one usually keeps
! the original, larger files. For simplicity, ensure all files follow FLUSI
! naming convention.
!---
! Note: through using helpers.f90::get_dsetname, it is finally possible to write
! to a subfolder *.h5 file directly from flusi
! (Thomas, 03/2015)
!---
! Using HDF5s hyperslab functions, we can read only a specific part into the
! memory - at no point we have to load the entire original file before we can
! downsample it. This is a good step forward. (Thomas 03/2015)
!-------------------------------------------------------------------------------
! call:
! ./flusi --postprocess --extract-subset ux_00000.h5 sux_00000.h5 128:1:256 128:2:1024 1:1:9999
!-------------------------------------------------------------------------------
subroutine extract_subset(help)
  use mpi
  use vars
  use hdf5
  use basic_operators
  use helpers
  implicit none

  logical, intent(in) :: help
  character(len=strlen) :: fname_in, fname_out, dsetname_in, dsetname_out
  character(len=strlen) :: xset,yset,zset
  integer :: ix,iy,iz,i
  ! reduced domain size
  integer :: nx1,nx2, ny1,ny2, nz1,nz2, nxs,nys,nzs
  ! sizes of the new array
  integer :: nx_red, ny_red, nz_red, ix_red, iy_red, iz_red
  ! reduced domain extends
  real(kind=pr) :: xl1, yl1, zl1
  real(kind=pr), dimension(:,:,:), allocatable :: field

  integer, parameter            :: rank = 3 ! data dimensionality (2D or 3D)
  real (kind=pr)                :: time, xl_file, yl_file, zl_file
  character(len=80)             :: dsetname
  integer                       :: nx_file, ny_file, nz_file, mpierror

  integer(hid_t) :: file_id       ! file identifier
  integer(hid_t) :: dset_id       ! dataset identifier
  integer(hid_t) :: filespace     ! dataspace identifier in file
  integer(hid_t) :: memspace      ! dataspace identifier in memory
  integer(hid_t) :: plist_id      ! property list identifier

  ! dataset dimensions in the file.
  integer(hsize_t), dimension(rank) :: dimensions_file
  integer(hsize_t), dimension(rank) :: dimensions_local  ! chunks dimensions
  integer(hsize_t), dimension(rank) :: chunking_dims  ! chunks dimensions

  integer(hsize_t),  dimension(rank) :: count  = 1
  integer(hssize_t), dimension(rank) :: offset
  integer(hsize_t),  dimension(rank) :: stride = 1
  integer :: error  ! error flags

  ! what follows is for the attribute "time"
  integer, parameter :: arank = 1


  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --extract-subset ux_00000.h5 sux_00000.h5 128:1:256 128:2:1024 1:1:9999"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! extract subset"
    write(*,*) "! loads a file to memory and extracts a subset, writing to a different file. We"
    write(*,*) "! assume here that you do this for visualization; in this case, one usually keeps"
    write(*,*) "! the original, larger files. For simplicity, ensure all files follow FLUSI"
    write(*,*) "! naming convention."
    write(*,*) "!---"
    write(*,*) "! Note: through using helpers.f90::get_dsetname, it is finally possible to write"
    write(*,*) "! to a subfolder *.h5 file directly from flusi"
    write(*,*) "! (Thomas, 03/2015)"
    write(*,*) "!---"
    write(*,*) "! Using HDF5s hyperslab functions, we can read only a specific part into the"
    write(*,*) "! memory - at no point we have to load the entire original file before we can"
    write(*,*) "! downsample it. This is a good step forward. (Thomas 03/2015)"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: Nope"
    return
  endif


  if (mpisize/=1) then
    write(*,*) "./flusi --postprocess --extract-subset is a SERIAL routine, use 1CPU only"
    call abort(7102)
  endif

  ! get file to read pressure from and check if this is present
  call get_command_argument(3,fname_in)
  call check_file_exists( fname_in )

  ! get filename to save subset to
  call get_command_argument(4,fname_out)

  dsetname_in  = get_dsetname( fname_in )
  dsetname_out = get_dsetname( fname_out )

  write(*,'("dsetname=",A,1x,A)') trim(adjustl(dsetname_in)),trim(adjustl(dsetname_out))

  call fetch_attributes( fname_in, nx, ny, nz, xl, yl, zl, time, nu )

  call get_command_argument(5,xset)
  call get_command_argument(6,yset)
  call get_command_argument(7,zset)

  ! red in subset from command line. it is given in the form
  ! ixmin:xspacing:ixmax as a string.
  read (xset(1:index(xset,':')-1) ,*) nx1
  read (xset(index(xset,':',.true.)+1:len_trim(xset)),*) nx2
  read (xset(index(xset,':')+1:index(xset,':',.true.)-1),*) nxs

  read (yset(1:index(yset,':')-1) ,*) ny1
  read (yset(index(yset,':',.true.)+1:len_trim(yset)),*) ny2
  read (yset(index(yset,':')+1:index(yset,':',.true.)-1),*) nys

  read (zset(1:index(zset,':')-1) ,*) nz1
  read (zset(index(zset,':',.true.)+1:len_trim(zset)),*) nz2
  read (zset(index(zset,':')+1:index(zset,':',.true.)-1),*) nzs


  ! stop if subset exceeds array bounds
  if ( nx1<0 .or. nx2>nx-1 .or. ny1<0 .or. ny2>ny-1 .or. nz1<0 .or. nz2>nz-1) then
    write (*,*) "subset indices exceed array bounds....proceed, but correct mistake"
    nx1 = max(nx1,0)
    ny1 = max(ny1,0)
    nz1 = max(nz1,0)
    nx2 = min(nx-1,nx2)
    ny2 = min(ny-1,ny2)
    nz2 = min(nz-1,nz2)
  endif


  write(*,'("Cropping field from " &
  &,"0:",i4," | 0:",i4," | 0:",i4,&
  &"   to subset   "&
  &,i4,":",i2,":",i4," | ",i4,":",i2,":",i4," | ",i4,":",i2,":",i4)')&
  nx-1,ny-1,nz-1,nx1,nxs,nx2,ny1,nys,ny2,nz1,nzs,nz2



  !-----------------------------------------------------------------------------
  ! compute dimensions of reduced subset:
  nx_red = nx1 + floor( dble(nx2-nx1)/dble(nxs) )  - nx1 + 1
  ny_red = ny1 + floor( dble(ny2-ny1)/dble(nys) )  - ny1 + 1
  nz_red = nz1 + floor( dble(nz2-nz1)/dble(nzs) )  - nz1 + 1
  write (*,'("Size of subset is ",3(i4,1x))') nx_red, ny_red, nz_red
  !-----------------------------------------------------------------------------

  ! we figured out how big the subset array is
  allocate ( field(0:nx_red-1,0:ny_red-1,0:nz_red-1) )


  call Fetch_attributes( fname_in, nx_file,ny_file,nz_file,&
  xl_file,yl_file,zl_file,time, nu )

  !-----------------------------------------------------------------------------
  ! load the file
  ! the basic idea is to just allocate the smaller field, and use hdf5
  ! to read just this field from the input file.
  !-----------------------------------------------------------------------------
  ! Initialize HDF5 library and Fortran interfaces.
  call h5open_f(error)

  ! Setup file access property list with parallel I/O access.  this
  ! sets up a property list ("plist_id") with standard values for
  ! FILE_ACCESS
  call h5pcreate_f(H5P_FILE_ACCESS_F, plist_id, error)
  ! this modifies the property list and stores MPI IO
  ! comminucator information in the file access property list
  call h5pset_fapl_mpio_f(plist_id, MPI_COMM_WORLD, MPI_INFO_NULL, error)
  ! open the file in parallel
  call h5fopen_f (fname_in, H5F_ACC_RDWR_F, file_id, error, plist_id)
  ! this closes the property list (we'll re-use it)
  call h5pclose_f(plist_id, error)

  ! Definition of memory distribution
  dimensions_file  = (/ nx_file, ny_file, nz_file/)
  dimensions_local = (/ nx_red , ny_red,  nz_red /)
  offset = (/ nx1, ny1, nz1 /)
  stride = (/ nxs, nys, nzs /)
  chunking_dims = 1 !min(nx_red,ny_red,nz_red)

  !----------------------------------------------------------------------------
  ! Read actual field from file (dataset)
  !----------------------------------------------------------------------------
  ! dataspace in the file: contains all data from all procs
  call h5screate_simple_f(rank, dimensions_file, filespace, error)
  ! dataspace in memory: contains only local data
  call h5screate_simple_f(rank, dimensions_local, memspace, error)

  ! Create chunked dataset
  call h5pcreate_f(H5P_DATASET_CREATE_F, plist_id, error)
  call h5pset_chunk_f(plist_id, rank, chunking_dims, error)

  ! Open an existing dataset.
  call h5dopen_f(file_id, dsetname_in, dset_id, error)

  ! Select hyperslab in the file.
  call h5dget_space_f(dset_id, filespace, error)
  call h5sselect_hyperslab_f (filespace, H5S_SELECT_SET_F, offset, dimensions_local, &
  error, stride, count)


  ! Create property list for collective dataset read
  call h5pcreate_f(H5P_DATASET_XFER_F, plist_id, error)
  call h5pset_dxpl_mpio_f(plist_id, H5FD_MPIO_COLLECTIVE_F, error)
  ! actual read is the next command:
  call h5dread_f( dset_id, H5T_NATIVE_DOUBLE, field, dimensions_local, error, &
  mem_space_id = memspace, file_space_id = filespace, xfer_prp = plist_id )

  ! check if we loaded crap
  call checknan(field,"recently loaded field")

  call h5sclose_f(filespace, error)
  call h5sclose_f(memspace, error)
  call h5pclose_f(plist_id, error)
  call h5dclose_f(dset_id, error)
  call h5fclose_f(file_id,error)
  call H5close_f(error)

  ! set up dimensions in global variables, since save_field_hdf5 relies on this
  ra = 0
  rb(1) = nx_red-1
  rb(2) = ny_red-1
  rb(3) = nz_red-1
  nx = nx_red
  ny = ny_red
  nz = nz_red
  dx = xl_file / dble(nx_file)
  dy = yl_file / dble(ny_file)
  dz = zl_file / dble(nz_file)
  xl = dx + dble(nx1+(nx_red-1)*nxs)*dx - dble(nx1)*dx
  yl = dy + dble(ny1+(ny_red-1)*nys)*dy - dble(ny1)*dy
  zl = dz + dble(nz1+(nz_red-1)*nzs)*dz - dble(nz1)*dz

  ! Done! Write extracted subset to disk and be happy with the result
  call save_field_hdf5 ( time, fname_out, field )

end subroutine extract_subset


!-------------------------------------------------------------------------------
! copy one hdf5 file to another one, with different name. Not you cannot do this
! in terminal with "cp" since "cp" does not touch the dataset name in the file,
! which is then not conformal to flusi naming convention.
! call:
! ./flusi --postprocess --cp ux_00000.h5 new_00000.h5
!
!
! since I learned about h5copy tool, this subroutine is deprecated
!
! h5copy -i mask_000000.h5 -s mask -o hallo.h5 -d test
!
!-------------------------------------------------------------------------------
subroutine copy_hdf_file(help)
  use mpi
  use vars
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_in, fname_out
  real(kind=pr)::time
  ! input field
  real(kind=pr), dimension(:,:,:), allocatable :: field_in

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "/flusi --postprocess --cp ux_00000.h5 new_00000.h5 "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! copy one hdf5 file to another one, with different name. Not you cannot do this"
    write(*,*) "! in terminal with cp since cp does not touch the dataset name in the file,"
    write(*,*) "! which is then not conformal to flusi naming convention."
    write(*,*) "!"
    write(*,*) "! since I learned about h5copy tool, this subroutine is deprecated"
    write(*,*) "!"
    write(*,*) "! h5copy -i mask_000000.h5 -s mask -o hallo.h5 -d test"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: no"
    return
  endif


  if (mpisize/=1) then
    write(*,*) "./flusi --postprocess --cp is a SERIAL routine, use 1CPU only"
    call abort(7103)
  endif



  ! get file to read pressure from and check if this is present
  call get_command_argument(3,fname_in)
  call check_file_exists( fname_in )

  ! get filename to save file to
  call get_command_argument(4,fname_out)

  call fetch_attributes( fname_in, nx, ny, nz, xl, yl, zl, time, nu )
  ra=0
  rb=(/nx-1,ny-1,nz-1/)
  write(*,*) "copying ",trim(adjustl(fname_in)), " to ", trim(adjustl(fname_out))

  allocate ( field_in(0:nx-1,0:ny-1,0:nz-1) )
  call read_single_file(fname_in,field_in)

  call save_field_hdf5 ( time, fname_out, field_in )

  deallocate (field_in)
end subroutine copy_hdf_file




!-------------------------------------------------------------------------------
! Add or modifiy an attribute to the dataset stored in a HDF5 file.
! This is useful for example if one creates stroke-averaged fields
! that would all have the same time 0.0.
! We also want to use this to add new attributes to our data, namely the
! viscosity
!-------------------------------------------------------------------------------
! ./flusi -p --set-hdf5-attrbute [FILE] [ATTRIBUTE_NAME] [ATTRIBUTE_VALUE(S)]
!-------------------------------------------------------------------------------
subroutine set_hdf5_attribute(help)
  use mpi
  use hdf5
  use vars
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname, attribute_name, dsetname,tmp
  integer :: error

  integer(hid_t) :: file_id       ! file identifier
  integer(hid_t) :: dset_id       ! dataset identifier
  integer(hid_t) :: attr_id       ! attribute identifier
  integer(hid_t) :: aspace_id     ! attribute dataspace identifier
  integer(hsize_t), dimension(1) :: data_dims
  real(kind=pr) ::  attr_data  ! attribute data
  real(kind=pr) :: new_value

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --set-hdf5-attrbute [FILE] [ATTRIBUTE_NAME] [ATTRIBUTE_VALUE(S)]"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! Add or modifiy an attribute to the dataset stored in a HDF5 file."
    write(*,*) "! This is useful for example if one creates stroke-averaged fields"
    write(*,*) "! that would all have the same time 0.0."
    write(*,*) "! We also want to use this to add new attributes to our data, namely the"
    write(*,*) "! viscosity"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: no"
    return
  endif


  data_dims(1) = 1

  ! get file to read pressure from and check if this is present
  call get_command_argument(3,fname)
  call check_file_exists( fname )
  dsetname = get_dsetname(fname)

  ! get filename to save file to
  call get_command_argument(4,attribute_name)
  call get_command_argument(5,tmp)
  read(tmp,*) new_value

  ! Initialize FORTRAN interface.
  CALL h5open_f(error)
  ! Open an existing file.
  CALL h5fopen_f (fname, H5F_ACC_RDWR_F, file_id, error)
  ! Open an existing dataset.
  CALL h5dopen_f(file_id, dsetname, dset_id, error)

  if(mpirank==0) then
    write(*,'(80("-"))')
    write (*,*) "FLUSI tries to open the attribute in the file..."
  endif

  ! try to open the attribute
  CALL h5aopen_f(dset_id, trim(adjustl(attribute_name)), attr_id, error)

  if (error == 0) then
    if(mpirank==0) then
      write (*,*) "succesful! The file already contains the attribute"
      write(*,'(80("-"))')
    endif
    ! the attribute is already a part of the HDF5 file
    ! Get dataspace and read
    CALL h5aget_space_f(attr_id, aspace_id, error)
    ! read
    CALL h5aread_f( attr_id, H5T_NATIVE_DOUBLE, attr_data, data_dims, error)
    if(mpirank==0) then
      write(*,'("old value of ",A," is ",es15.8)') trim(adjustl(attribute_name)), attr_data
    endif
    ! write
    call h5awrite_f(attr_id, H5T_NATIVE_DOUBLE, (/new_value/), data_dims, error)
    ! Close the attribute.
    CALL h5aclose_f(attr_id, error)
    ! Terminate access to the data space.
    CALL h5sclose_f(aspace_id, error)
  else
    ! the attribute is NOT a part of the file yet, we add it now
    if(mpirank==0) then
      write(*,*) "fail: the file did not yet contain this attribute, adding it!"
      write(*,'(80("-"))')
    endif
    call write_attribute_dble(data_dims,trim(adjustl(attribute_name)),(/new_value/),1,dset_id)
  endif

  ! check if everthing worked
  if(mpirank==0) write(*,*) "checking if the operation worked..."
  ! try to open the attribute
  CALL h5aopen_f(dset_id, trim(adjustl(attribute_name)), attr_id, error)
  CALL h5aread_f( attr_id, H5T_NATIVE_DOUBLE, attr_data, data_dims, error)

  if(mpirank==0) write(*,'(A,"=",g12.4)') trim(adjustl(attribute_name)), attr_data

  ! finalize HDF5
  CALL h5dclose_f(dset_id, error) ! End access to the dataset and release resources used by it.
  CALL h5fclose_f(file_id, error) ! Close the file.
  CALL h5close_f(error)  ! Close FORTRAN interface.

end subroutine set_hdf5_attribute



!-------------------------------------------------------------------------------
! Upsampling from a source resolution to a target resolution
! ./flusi -p --upsample source.h5 target.h5 256 256 526
!-------------------------------------------------------------------------------
! We first read in the original field from the source file, with it's resolution
! and domain size and timestamp.
!-------------------------------------------------------------------------------
subroutine upsample(help)
  use vars
  use p3dfft_wrapper
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_in, fname_out, tmp
  integer :: nx_new, ny_new, nz_new
  integer :: nx_org, ny_org, nz_org, ix_org,iy_org,iz_org, ix_new,iy_new,iz_new
  integer :: i,j,k
  real(kind=pr) :: time, kx_org,ky_org,kz_org, kx_new,ky_new,kz_new
  complex(kind=pr),dimension(:,:,:),allocatable :: uk_org, uk_new
  real(kind=pr),dimension(:,:,:),allocatable :: u_org, u_new
  integer, dimension(1:3) :: ra_org,rb_org,ca_org,cb_org,ra_new,rb_new,ca_new,cb_new

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --upsample source.h5 target.h5 256 256 526"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Upsampling from a source resolution to a target resolution"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: no"
    return
  endif



  if (mpisize/=1) then
    write(*,*) "./flusi --postprocess --upsample is a SERIAL routine, use 1CPU only"
    call abort(7104)
  endif

  ! get file to read pressure from and check if this is present
  call get_command_argument(3,fname_in)
  call check_file_exists( fname_in )

  call get_command_argument(4,fname_out)

  ! read target resolution from command line
  call get_command_argument(5,tmp)
  read (tmp,*) nx_new
  call get_command_argument(6,tmp)
  read (tmp,*) ny_new
  call get_command_argument(7,tmp)
  read (tmp,*) nz_new

  write(*,'("Target resolution= ",3(i4,1x))') nx_new, ny_new, nz_new

  call fetch_attributes( fname_in, nx_org, ny_org, nz_org, xl, yl, zl, time, nu )
  write(*,'("Origin resolution= ",3(i4,1x))') nx_org,ny_org,nz_org

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl


  !-----------------------
  write(*,*) "Initializing small FFT and transforming source field to k-space"
  nx = nx_org
  ny = ny_org
  nz = nz_org
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)
  call fft_initialize
  ra_org = ra
  rb_org = rb
  ca_org = ca
  cb_org = cb
  !-----------------------

  allocate(u_org(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))
  allocate(uk_org(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3)))

  call fft_unit_test( u_org, uk_org )

  write(*,*) "Reading file "//trim(adjustl(fname_in))
  call read_single_file(fname_in,u_org)

  call fft(inx=u_org, outk=uk_org)

  deallocate(u_org)

  call fft_free
  !-----------------------
  write(*,*) "Initializing big FFT and copying source Fourier coefficients to &
  & target field in k-space"

  nx=nx_new
  ny=ny_new
  nz=nz_new
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)
  call fft_initialize
  ra_new = ra
  rb_new = rb
  ca_new = ca
  cb_new = cb
  !-----------------------

  allocate(u_new(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))
  allocate(uk_new(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3)))
  call fft_unit_test( u_new, uk_new )
  uk_new = dcmplx(0.d0,0.d0)

  !------------------------------------------------------------------
  do iz_org=ca_org(1),cb_org(1)
    nx=nx_org; ny=ny_org; nz=nz_org
    kz_org=wave_z(iz_org)
    ! find corresponding iz_new
    do iz_new=ca_new(1),cb_new(1)
      nx=nx_new; ny=ny_new; nz=nz_new
      kz_new = wave_z(iz_new)
      if (kz_new==kz_org) exit
    enddo
    ! we now have the pair (iz_org, iz_new)
    !------------------------------------------------------------------
    do iy_org=ca_org(2),cb_org(2)
      nx=nx_org; ny=ny_org; nz=nz_org
      ky_org=wave_y(iy_org)
      ! find corresponding iz_new
      do iy_new=ca_new(2),cb_new(2)
        nx=nx_new; ny=ny_new; nz=nz_new
        ky_new = wave_y(iy_new)
        if (ky_new==ky_org) exit
      enddo
      ! we now have the pair (iy_org, iy_new)
      !------------------------------------------------------------------
      do ix_org=ca_org(3),cb_org(3)
        nx=nx_org; ny=ny_org; nz=nz_org
        kx_org=wave_x(ix_org)
        ! find corresponding iz_new
        do ix_new=ca_new(3),cb_new(3)
          nx=nx_new; ny=ny_new; nz=nz_new
          kx_new = wave_x(ix_new)
          if (kx_new==kx_org) exit
        enddo
        ! we now have the pair (ix_org, ix_new)

        ! copy the old Fourier coefficients to the new field
        uk_new(iz_new,iy_new,ix_new) = uk_org(iz_org,iy_org,ix_org)
      enddo
    enddo
  enddo

  deallocate( uk_org )

  ! transform the zero-padded Fourier coefficients back to physical space. this
  ! is the upsampled (=interpolated) field.
  write(*,*) "transforming zero-padded Fourier coefficients back to x-space"
  call ifft(ink=uk_new,outx=u_new)

  deallocate( uk_new )

  ! save the final result to the specified file
  write(*,*) "Saving upsampled field to " // trim(adjustl(fname_out))
  call save_field_hdf5(time,fname_out,u_new)

  deallocate( u_new )
end subroutine upsample


!-------------------------------------------------------------------------------
! ./flusi --postprocess --spectrum ux_00000.h5 uy_00000.h5 uz_00000.h5 spectrum.dat
!-------------------------------------------------------------------------------
! NOTE: I actually did not figure out what happens if xl=yl=zl/=2*pi
! which is a rare case in all isotropic turbulence situtations, and neither
! of the corresponding routines have been tested for that case.
subroutine post_spectrum(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, spectrum_file
  complex(kind=pr),dimension(:,:,:,:),allocatable :: uk
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr) :: time, sum_u
  real(kind=pr), dimension(:), allocatable :: S_Ekinx,S_Ekiny,S_Ekinz,S_Ekin
  integer :: mpicode, k

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --spectrum ux_00000.h5 uy_00000.h5 uz_00000.h5 spectrum.dat"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif

  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,spectrum_file)

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  if ((fname_ux(1:2).ne."ux").or.(fname_uy(1:2).ne."uy").or.(fname_uz(1:2).ne."uz")) then
    write (*,*) "Error in arguments, files do not start with ux uy and uz"
    write (*,*) "note files have to be in the right order"
    call abort(7105)
  endif

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  if (mpirank==0) then
    write(*,'("Computing spectrum of ",A,1x,A,1x,A)') &
    trim(adjustl(fname_ux)), trim(adjustl(fname_uy)), trim(adjustl(fname_uz))
    write(*,'("Spectrum will be written to ",A)') trim(adjustl(spectrum_file))
    write(*,'("Resolution is ",i4,1x,i4,1x,i4)') nx, ny, nz
    write(*,'("Domain size is", es12.4,1x,es12.4,1x,es12.4)') xl, yl ,zl
  endif

  call fft_initialize() ! also initializes the domain decomp


  call MPI_barrier (MPI_COMM_world, mpicode)
  write (*,'("mpirank=",i5," x-space=(",i4,":",i4," |",i4,":",i4," |",i4,":",i4,&
  &") k-space=(",i4,":",i4," |",i4,":",i4," |",i4,":",i4,")")') &
  mpirank, ra(1),rb(1), ra(2),rb(2),ra(3),rb(3), ca(1),cb(1), ca(2),cb(2),ca(3),cb(3)
  call MPI_barrier (MPI_COMM_world, mpicode)


  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))
  allocate(S_Ekinx(0:nx-1),S_Ekiny(0:nx-1),S_Ekinz(0:nx-1),S_Ekin(0:nx-1))

  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  call fft (uk(:,:,:,1),u(:,:,:,1))
  call fft (uk(:,:,:,2),u(:,:,:,2))
  call fft (uk(:,:,:,3),u(:,:,:,3))

  ! compute the actual spectrum
  call compute_spectrum( time,uk,S_Ekinx,S_Ekiny,S_Ekinz,S_Ekin )

  ! on root, write it to disk
  if (mpirank == 0) then
    open(10,file=spectrum_file,status='replace')
    write(10,'(5(A15,1x))') '%   K ','E_u(K)','E_ux(K)','E_uy(K)','E_uz(K)'
    do k=0,nx-1
      write(10,'(5(1x,es15.8))') dble(k),S_Ekin(k),S_Ekinx(k),S_Ekiny(k),S_Ekinz(k)
    enddo

    sum_u=0.0d0
    do k=1,nx-1
      sum_u=sum_u +S_Ekin(k)
    enddo
    write(10,*) '% Etot = ',sum_u
    write(10,*) '% time = ',time
    close(10)
  endif

  deallocate (u)
  deallocate (uk)
  deallocate(S_Ekinx,S_Ekiny,S_Ekinz,S_Ekin)
  call fft_free()

end subroutine post_spectrum


!-------------------------------------------------------------------------------
! ./flusi --postprocess --turbulence-analysis ux_00000.h5 uy_00000.h5 uz_00000.h5 nu outfile.dat
! NOTE: I actually did not figure out what happens if xl=yl=zl/=2*pi
! which is a rare case in all isotropic turbulence situtations, and neither
! of the corresponding routines have been tested for that case.
!-------------------------------------------------------------------------------
subroutine turbulence_analysis(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, viscosity, outfile
  complex(kind=pr),dimension(:,:,:,:),allocatable :: uk,vork
  real(kind=pr),dimension(:,:,:,:),allocatable :: u, vor
  real(kind=pr) :: time, epsilon_loc, epsilon, fact, E, u_rms,lambda_macro,lambda_micro
  real(kind=pr), dimension(:), allocatable :: S_Ekinx,S_Ekiny,S_Ekinz,S_Ekin
  integer :: ix,iy,iz, mpicode
  real(kind=pr)::kx,ky,kz,kreal

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --turbulence-analysis ux_00000.h5 uy_00000.h5 uz_00000.h5 nu outfile.dat"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "compute a bunch of values relevant to Homogeneous isotropic turbulence and write them to outfile"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,viscosity)
  call get_command_argument(7,outfile)
  read(viscosity,*) nu

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  if ((fname_ux(1:2).ne."ux").or.(fname_uy(1:2).ne."uy").or.(fname_uz(1:2).ne."uz")) then
    write (*,*) "Error in arguments, files do not start with ux uy and uz"
    write (*,*) "note files have to be in the right order"
    call abort(7106)
  endif

  if(mpirank==0) then
    write(*,*) " OUTPUT will be written to "//trim(adjustl(outfile))
    open(17,file=trim(adjustl(outfile)),status='replace')
    call postprocessing_ascii_header(17)
    write(17,'(A)') "-----------------------------------"
    write(17,'(A)') "FLUSI turbulence analysis"
    write(17,'("call: ./flusi -p --turbulence-analysis ",5(A,1x))') trim(adjustl(fname_ux)),&
    trim(adjustl(fname_uy)),trim(adjustl(fname_uz)),trim(adjustl(viscosity)),trim(adjustl(outfile))
    write(17,'(A)') "-----------------------------------"
  endif

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))
  allocate(vor(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(vork(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))
  allocate(S_Ekinx(0:nx-1),S_Ekiny(0:nx-1),S_Ekinz(0:nx-1),S_Ekin(0:nx-1))

  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  call fft3 (inx=u,outk=uk)
  call curl (uk,vork)
  call ifft3 (ink=vork,outx=vor)

  ! compute spectrum
  call compute_spectrum( time,uk,S_Ekinx,S_Ekiny,S_Ekinz,S_Ekin )

  !-----------------------------------------------------------------------------
  ! dissipation rate from velocity in Fourier space
  !-----------------------------------------------------------------------------
  do iz=ca(1),cb(1)
    kz=wave_z(iz)
    do iy=ca(2),cb(2)
      ky=wave_y(iy)
      do ix=ca(3),cb(3)
        kx=wave_x(ix)
        kreal = ( (kx*kx)+(ky*ky)+(kz*kz) )

        if ( ix==0 .or. ix==nx/2 ) then
          E=dble(real(uk(iz,iy,ix,1))**2+aimag(uk(iz,iy,ix,1))**2)/2. &
          +dble(real(uk(iz,iy,ix,2))**2+aimag(uk(iz,iy,ix,2))**2)/2. &
          +dble(real(uk(iz,iy,ix,3))**2+aimag(uk(iz,iy,ix,3))**2)/2.
        else
          E=dble(real(uk(iz,iy,ix,1))**2+aimag(uk(iz,iy,ix,1))**2) &
          +dble(real(uk(iz,iy,ix,2))**2+aimag(uk(iz,iy,ix,2))**2) &
          +dble(real(uk(iz,iy,ix,3))**2+aimag(uk(iz,iy,ix,3))**2)
        endif

        epsilon_loc = epsilon_loc + kreal * E
      enddo
    enddo
  enddo

  epsilon_loc = 2.d0 * nu * epsilon_loc

  call MPI_ALLREDUCE(epsilon_loc,epsilon,1,MPI_DOUBLE_PRECISION,MPI_SUM,&
  MPI_COMM_WORLD,mpicode)

  if (mpirank==0) then
    write(17,'(g15.8,5x,A)') epsilon, "Dissipation rate from velocity in Fourier space"
  endif



  !-----------------------------------------------------------------------------
  ! dissipation rate from vorticty
  !-----------------------------------------------------------------------------
  epsilon_loc = nu * sum(vor(:,:,:,1)**2+vor(:,:,:,2)**2+vor(:,:,:,3)**2)
  call MPI_REDUCE(epsilon_loc,epsilon,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
  MPI_COMM_WORLD,mpicode)

  if (mpirank==0) then
    write(17,'(g15.8,5x,A)') epsilon/(dble(nx)*dble(ny)*dble(nz)), "Dissipation rate from vorticity"
  endif

  !-----------------------------------------------------------------------------
  ! dissipation rate from spectrum; see Ishihara, Kaneda "High
  ! resolution DNS of incompressible Homogeneous forced turbulence -time dependence
  ! of the statistics" or my thesis
  !-----------------------------------------------------------------------------
  if (mpirank==0) then
    epsilon=0.0
    do ix = 0,nx-1
      epsilon = epsilon + 2.d0 * nu * dble(ix**2) * S_Ekin(ix)
    enddo
    write(17,'(g15.8,5x,A)') epsilon, "Dissipation rate from spectrum"
  endif

  !-----------------------------------------------------------------------------
  ! energy from velocity
  !-----------------------------------------------------------------------------
  epsilon_loc = 0.5d0*sum(u(:,:,:,1)**2+u(:,:,:,2)**2+u(:,:,:,3)**2)
  call MPI_REDUCE(epsilon_loc,E,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
  MPI_COMM_WORLD,mpicode)

  if (mpirank==0) then
    write(17,'(g15.8,5x,A)') E/(dble(nx)*dble(ny)*dble(nz)), "energy from velocity"
  endif

  !-----------------------------------------------------------------------------
  ! energy from spectrum
  !-----------------------------------------------------------------------------
  if (mpirank==0) then
    E=0.0
    do ix = 0,nx-1
      E = E + S_Ekin(ix)
    enddo
    write(17,'(g15.8,5x,A)') E, "energy from spectrum"
  endif

  u_rms=dsqrt(2.d0*E/3.d0)
  !-----------------------------------------------------------------------------
  ! kolmogrov scales
  !-----------------------------------------------------------------------------
  if (mpirank==0) then
    write(17,'(g15.8,5x,A)') (nu**3 / epsilon)**(0.25d0), "kolmogorov length scale"
    write(17,'(g15.8,5x,A)') (nu / epsilon)**(0.5d0), "kolmogorov time scale"
    write(17,'(g15.8,5x,A)') (nu*epsilon)**(0.25d0), "kolmogorov velocity scale"
    write(17,'(g15.8,5x,A)') u_rms, "RMS velocity"
  endif

  !-----------------------------------------------------------------------------
  ! taylor scales
  !-----------------------------------------------------------------------------
  if (mpirank==0) then
    lambda_micro = (15.d0*nu*u_rms**2 / epsilon)**(0.5d0)
    lambda_macro=0.0
    do ix = 1,nx-1
      lambda_macro = lambda_macro + pi/(2.d0*u_rms**2) * S_Ekin(ix) / dble(ix)
    enddo
    write(17,'(g15.8,5x,A)') lambda_micro, "taylor micro scale"
    write(17,'(g15.8,5x,A)') lambda_macro, "taylor macro scale"
    write(17,'(g15.8,5x,A)') u_rms*lambda_macro/nu, "Renolds taylor macro scale"
    write(17,'(g15.8,5x,A)') u_rms*lambda_micro/nu, "Renolds taylor micro scale"
    write(17,'(g15.8,5x,A)') lambda_macro/u_rms, "eddy turnover time"
    write(17,'(g15.8,5x,A)') (2./3.)*(dble(nx/2-1)), "kmax"
    write(17,'(g15.8,5x,A)') (2./3.)*(dble(nx/2-1))*(nu**3 / epsilon)**(0.25d0), "kmax*eta"
  endif

  if(mpirank==0) close(17)

  deallocate (u,vor,vork)
  deallocate (uk)
  deallocate (S_Ekinx,S_Ekiny,S_Ekinz,S_Ekin)
  call fft_free()

end subroutine turbulence_analysis


!-------------------------------------------------------------------------------
! ./flusi -p --TKE-mean ekinavg_00.h5 uavgx_00.h5 uavgy_00.h5 uavgz_00.h5 tkeavg_000.h5
! From the time-avg kinetic energy field and the components of the time avg
! velocity field, compute the time averaged turbulent kinetic energy.
! See TKE note 18 feb 2015 (Thomas) and 13 feb 2015 (Dmitry)
! Can be done in parallel
!-------------------------------------------------------------------------------
subroutine TKE_mean(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, fname_ekin, outfile
  real(kind=pr),dimension(:,:,: ),allocatable :: ekin
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr) :: time

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --TKE-mean ekinavg_00.h5 uavgx_00.h5 uavgy_00.h5 uavgz_00.h5 tkeavg_000.h5"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! From the time-avg kinetic energy field and the components of the time avg"
    write(*,*) "! velocity field, compute the time averaged turbulent kinetic energy."
    write(*,*) "! See TKE note 18 feb 2015 (Thomas) and 13 feb 2015 (Dmitry)"
    write(*,*) "! TKE = ekin - 0.5d0*(ux^2 + uy^2 + uz^2)"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,fname_ekin)
  call get_command_argument(4,fname_ux)
  call get_command_argument(5,fname_uy)
  call get_command_argument(6,fname_uz)
  call get_command_argument(7,outfile)

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )
  call check_file_exists( fname_ekin )

  if (mpirank == 0) then
    write(*,*) "Processing "//trim(adjustl(fname_ux))//" "//trim(adjustl(fname_uy))//&
    &" "//trim(adjustl(fname_uz))//" and "//fname_ekin
  endif

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(ekin(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))

  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )
  call read_single_file ( fname_ekin, ekin )

  ekin = ekin - 0.5d0*(u(:,:,:,1)**2 + u(:,:,:,2)**2 + u(:,:,:,3)**2)

  if (mpirank==0) write(*,*) "Wrote to "//trim(adjustl(outfile))
  call save_field_hdf5 ( time,outfile,ekin)


  deallocate (u,ekin)
  call fft_free()

end subroutine tke_mean


!-------------------------------------------------------------------------------
! ./flusi -p --max-over-x tkeavg_000.h5 outfile.dat
! This function reads in the specified *.h5 file and outputs the maximum value
! max_yz(x) into the specified ascii-outfile
! It may be used rarely, but we needed it for turbulent bumblebees.
! Can be done in parallel.
!-------------------------------------------------------------------------------
subroutine max_over_x(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ekin, outfile
  real(kind=pr),dimension(:,:,:),allocatable :: u
  real(kind=pr), dimension(:), allocatable :: umaxx,umaxx_loc
  real(kind=pr) :: time
  integer :: ix, mpicode

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --max-over-x tkeavg_000.h5 outfile.dat"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! This function reads in the specified *.h5 file and outputs the maximum value"
    write(*,*) "! max_yz(x) into the specified ascii-outfile"
    write(*,*) "! It may be used rarely, but we needed it for turbulent bumblebees."
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,fname_ekin)
  call get_command_argument(4,outfile)
  call check_file_exists( fname_ekin )

  call fetch_attributes( fname_ekin, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate( u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)) )
  allocate( umaxx(0:nx-1) )
  allocate( umaxx_loc(0:nx-1) )

  call read_single_file ( fname_ekin, u )

  do ix=0,nx-1
    umaxx_loc(ix)=maxval(u(ix,:,:))
  enddo

  call MPI_ALLREDUCE(umaxx_loc,umaxx,nx,MPI_DOUBLE_PRECISION,MPI_MAX,&
  MPI_COMM_WORLD,mpicode)

  if(mpirank==0) then
    write(*,*) " OUTPUT will be written to "//trim(adjustl(outfile))
    open(17,file=trim(adjustl(outfile)),status='replace')
    write(17,'(A)') "%-----------------------------------"
    write(17,'(A)') "%FLUSI max-over-x file="//trim(adjustl(fname_ekin))
    write(17,'(A)') "%-----------------------------------"
    do ix=0,nx-1
      write(17,'(es15.8)') umaxx(ix)
    enddo
    close(17)
  endif



  deallocate (u,umaxx,umaxx_loc)
  call fft_free()

end subroutine max_over_x



!-------------------------------------------------------------------------------
! ./flusi -p --mean-2D [x,y,z] infile_000.h5 outfile.dat
! This function reads in the specified *.h5 file and outputs the average over two
! directions as a function of the remaining direction.
! e.g., ./flusi -p --mean-2D z infile_000.h5 outfile.dat
! averages over the x and y direction
! e.g., ./flusi -p --mean-2D all infile_000.h5 outfile.dat
! will loop over x,y,z and output all three to different files
!-------------------------------------------------------------------------------
subroutine mean_2d(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use helpers
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: infile, outfile, direction
  real(kind=pr),dimension(:,:,:),allocatable :: u
  real(kind=pr) :: time
  integer :: ix,iy,iz

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --mean-2D [x,y,z,all] infile_000.h5 outfile.dat"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! This function reads in the specified *.h5 file and outputs the average over two"
    write(*,*) "! directions as a function of the remaining direction."
    write(*,*) "! e.g., ./flusi -p --mean-2D z infile_000.h5 outfile.dat"
    write(*,*) "! averages over the x and y direction"
    write(*,*) "! e.g., ./flusi -p --mean-2D all infile_000.h5 outfile.dat"
    write(*,*) "! will loop over x,y,z and output all three to different files"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: nope"
    return
  endif


  if (mpisize/=1) then
    ! the reason for this is simplicity. if the y-z direction is nonlocal in memory
    ! the avg is more complicated. only the x direction is always contiguous.
    ! Plus: this acts on one field only, and it usually fits in the memory.
    call abort(7109,"./flusi --postprocess --mean-2D is a SERIAL routine, use 1CPU only")
  endif

  call get_command_argument(3,direction)
  call get_command_argument(4,infile)
  call get_command_argument(5,outfile)
  call check_file_exists( infile )

  write(*,*) "computing average in a 2D plane"
  write(*,*) "infile="//trim(adjustl(infile))
  write(*,*) "outfile="//trim(adjustl(outfile))

  call fetch_attributes( infile, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  ! allocate memory and read file
  allocate( u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)) )
  call read_single_file ( infile, u )


  !-----------------------------------------------------------------------------
  ! the rest of the code depends on the direction
  !-----------------------------------------------------------------------------
  select case (direction)
  case ("x")
      open(17,file=trim(adjustl(outfile)),status='replace')
      call postprocessing_ascii_header(17)
      write(17,'(A)') "%-----------------------------------"
      write(17,'(A)') "% FLUSI --mean-2D file="//trim(adjustl(infile))
      write(17,'(A)') "% direction="//trim(adjustl(direction))
      write(17,'(A)') "%-----------------------------------"
      write(*,*) "using X direction, thus averaging over y-z"
      ! compute actual mean value in the y-z plane, directly write to file
      do ix=0,nx-1
        write(17,'(es15.8)') sum( u(ix,:,:) ) / dble(ny*nz)
      enddo
      close(17)
  case ("y")
      open(17,file=trim(adjustl(outfile)),status='replace')
      call postprocessing_ascii_header(17)
      write(17,'(A)') "%-----------------------------------"
      write(17,'(A)') "% FLUSI --mean-2D file="//trim(adjustl(infile))
      write(17,'(A)') "% direction="//trim(adjustl(direction))
      write(17,'(A)') "%-----------------------------------"
      write(*,*) "using Y direction, thus averaging over x-z"
      ! compute actual mean value in the x-z plane, directly write to file
      do iy=0,ny-1
        write(17,'(es15.8)') sum( u(:,iy,:) ) / dble(nx*nz)
      enddo
      close(17)
  case ("z")
      open(17,file=trim(adjustl(outfile)),status='replace')
      call postprocessing_ascii_header(17)
      write(17,'(A)') "%-----------------------------------"
      write(17,'(A)') "% FLUSI --mean-2D file="//trim(adjustl(infile))
      write(17,'(A)') "% direction="//trim(adjustl(direction))
      write(17,'(A)') "%-----------------------------------"
      write(*,*) "using Z direction, thus averaging over x-y"
      ! compute actual mean value in the y-z plane, directly write to file
      do iz=0,nz-1
        write(17,'(es15.8)') sum( u(:,:,iz) ) / dble(ny*nx)
      enddo
      close(17)
  case ("all")
      write(*,*) "we compute all three possible averages"
      write(*,*) "--------------------------------------"
      write(*,*) "using X direction, thus averaging over y-z"
      ! compute actual mean value in the y-z planes, directly write to file
      open(17,file=trim(adjustl(outfile))//"_x",status='replace')
      call postprocessing_ascii_header(17)
      write(17,'(A)') "%-----------------------------------"
      write(17,'(A)') "% FLUSI --mean-2D file="//trim(adjustl(infile))
      write(17,'(A)') "% direction="//trim(adjustl(direction))
      write(17,'(A)') "%-----------------------------------"
      do ix=0,nx-1
        write(17,'(es15.8)') sum( u(ix,:,:) ) / dble(ny*nz)
      enddo
      close(17)

      write(*,*) "using Y direction, thus averaging over x-z"
      ! compute actual mean value in the x-z plane, directly write to file
      open(17,file=trim(adjustl(outfile))//"_y",status='replace')
      call postprocessing_ascii_header(17)
      write(17,'(A)') "%-----------------------------------"
      write(17,'(A)') "% FLUSI --mean-2D file="//trim(adjustl(infile))
      write(17,'(A)') "% direction="//trim(adjustl(direction))
      write(17,'(A)') "%-----------------------------------"
      do iy=0,ny-1
        write(17,'(es15.8)') sum( u(:,iy,:) ) / dble(nx*nz)
      enddo
      close(17)

      write(*,*) "using Z direction, thus averaging over x-y"
      ! compute actual mean value in the y-z plane, directly write to file
      open(17,file=trim(adjustl(outfile))//"_z",status='replace')
      call postprocessing_ascii_header(17)
      write(17,'(A)') "%-----------------------------------"
      write(17,'(A)') "% FLUSI --mean-2D file="//trim(adjustl(infile))
      write(17,'(A)') "% direction="//trim(adjustl(direction))
      write(17,'(A)') "%-----------------------------------"
      do iz=0,nz-1
        write(17,'(es15.8)') sum( u(:,:,iz) ) / dble(ny*nx)
      enddo
      close(17)
  case default
      call abort(7199,"Bad choice for direction "//trim(adjustl(direction)) )
  end select

  deallocate (u)
  call fft_free()

end subroutine mean_2d




!-------------------------------------------------------------------------------
! ./flusi -p --mean_over_x_subdomain tkeavg_000.h5 outfile.dat
! Compute the avg value as a function of x for a subdomain [-1.3,1.3]x[-1.3,1.3]
! in the y-z plane
! Can be done in parallel.
!-------------------------------------------------------------------------------
subroutine mean_over_x_subdomain(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ekin, outfile
  real(kind=pr),dimension(:,:,:),allocatable :: u, mask
  real(kind=pr), dimension(:), allocatable :: umaxx,umaxx_loc
  real(kind=pr) :: time,x,y,z,points,allpoints
  integer :: ix,iy,iz, mpicode

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --mean_over_x_subdomain tkeavg_000.h5 outfile.dat "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Compute the avg value as a function of x for a subdomain [-1.3,1.3]x[-1.3,1.3] in the y-z plane"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,fname_ekin)
  call get_command_argument(4,outfile)
  call check_file_exists( fname_ekin )

  call fetch_attributes( fname_ekin, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate( u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)) )
  allocate( mask(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)) )
  allocate( umaxx(0:nx-1) )
  allocate( umaxx_loc(0:nx-1) )

  call read_single_file ( fname_ekin, u )

  ! set a 1/0 mask to cancel values out of the bounds we want
  mask =0.d0
  do iz=ra(3),rb(3)
    do iy=ra(2),rb(2)
      do ix=ra(1),rb(1)
        x=dble(ix)*dx-2.0
        ! note we center y,z in the middle
        y=dble(iy)*dy-0.5*yl
        z=dble(iz)*dz-0.5*zl
        ! is the point inside the valid bounds?
        if ( abs(y)<=1.3d0 .and. abs(z)<=1.3d0 ) then
          mask(ix, iy, iz) = 1.d0
        endif
      enddo
    enddo
  enddo

  ! check if we loaded bullshit
  call checknan(mask,"mask")
  call checknan(u,"energy")

  if (minval(u)<0.d0) then
    write(*,*) "Warning, E<0 will produce NaN...correct that"
    where (u<0.d0)
      u=0.d0
    end where
  endif

  ! make TU intensity out of e
  u = dsqrt(2.d0*u/3.d0) * mask

  umaxx_loc=0.d0
  umaxx=0.d0

  call checknan(u,"urms")

  do ix=0,nx-1
    if (sum(mask(ix,:,:))>0.d0) then
      umaxx_loc(ix)=sum(u(ix,:,:))
    else
      umaxx_loc(ix)=0.0
    endif
  enddo

  ! get results from all CPUs, gather on all ranks
  call MPI_ALLREDUCE(umaxx_loc,umaxx,nx,MPI_DOUBLE_PRECISION,MPI_SUM,&
  MPI_COMM_WORLD,mpicode)

  ! get total number of points from all CPUs
  points = sum(mask)/dble(nx)
  call MPI_ALLREDUCE(points,allpoints,1,MPI_DOUBLE_PRECISION,MPI_SUM,&
  MPI_COMM_WORLD,mpicode)


  if(mpirank==0) then
    write(*,*) " OUTPUT will be written to "//trim(adjustl(outfile))
    open(17,file=trim(adjustl(outfile)),status='replace')
    write(17,'(A)') "%-----------------------------------"
    write(17,'(A)') "%FLUSI mean over x (boxed) file="//trim(adjustl(fname_ekin))
    write(17,'(A)') "%-----------------------------------"
    do ix=0,nx-1
      write(17,'(es15.8)') umaxx(ix) / allpoints
    enddo
    close(17)
  endif



  deallocate (u,umaxx,umaxx_loc,mask)
  call fft_free()

end subroutine mean_over_x_subdomain



!-------------------------------------------------------------------------------
! ./flusi --postprocess --ux-from-uyuz ux_00000.h5 uy_00000.h5 uz_00000.h5
!-------------------------------------------------------------------------------
! compute missing ux component from given uy,uz components assuming incompressibility
subroutine ux_from_uyuz(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use mpi
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz
  complex(kind=pr),dimension(:,:,:,:),allocatable :: uk
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr) :: time
  integer :: ix,iy,iz
  real(kind=pr) :: kx,ky,kz

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --ux-from-uyuz ux_00000.h5 uy_00000.h5 uz_00000.h5 "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) " not working"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)

  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  if ((fname_ux(1:2).ne."ux").or.(fname_uy(1:2).ne."uy").or.(fname_uz(1:2).ne."uz")) then
    write (*,*) "Error in arguments, files do not start with ux uy and uz"
    write (*,*) "note files have to be in the right order"
    call abort(7200)
  endif

  call fetch_attributes( fname_uy, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))

  u =0.d0
  uk = dcmplx(0.d0,0.d0)

  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  call fft (uk(:,:,:,2),u(:,:,:,2))
  call fft (uk(:,:,:,3),u(:,:,:,3))

  call dealias(uk(:,:,:,2))
  call dealias(uk(:,:,:,3))

  do iz=ca(1),cb(1)
    !-- wavenumber in z-direction
    kz = wave_z(iz)
    do iy=ca(2), cb(2)
      !-- wavenumber in y-direction
      ky = wave_y(iy)
      do ix=ca(3), cb(3)
        !-- wavenumber in x-direction
        kx = wave_x(ix)
        if (kx > 1.0d-12) then
          uk(iz,iy,ix,1) = -(ky/kx)*uk(iz,iy,ix,2) -(kz/kx)*uk(iz,iy,ix,3)
        else
          uk(iz,iy,ix,1) = dcmplx(0.d0,0.d0)
        endif
      enddo
    enddo
  enddo
  call dealias(uk(:,:,:,1))
  call ifft (u(:,:,:,1),uk(:,:,:,1))

  ! call fft (inx=u(:,:,:,1),outk=uk(:,:,:,1))
  ! call ifft (u(:,:,:,1),uk(:,:,:,1))

  call save_field_hdf5 ( time,fname_ux,u(:,:,:,1))
  if (mpirank==0) write(*,*) "Wrote vorx to "//trim(fname_ux)

  deallocate (u)
  deallocate (uk)
  call fft_free()

end subroutine





!-------------------------------------------------------------------------------
! ./flusi -p --magnitude ux_00.h5 uy_00.h5 uz_00.h5 outfile_00.h5
!-------------------------------------------------------------------------------
! load the vector components from file and compute & save the magnitude to
! another HDF5 file.
subroutine magnitude_post(help)
  use vars
  use basic_operators
  use p3dfft_wrapper
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, outfile
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr),dimension(:,:,:),allocatable :: work
  real(kind=pr) :: time

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --magnitude ux_00.h5 uy_00.h5 uz_00.h5 outfile_00.h5 "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! load the vector components from file and compute & save the magnitude to"
    write(*,*) "! another HDF5 file. mag(u) = sqrt(ux^2+uy^2+uz^2)  "
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif

  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,outfile)

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  if (mpirank==0) then
    write(*,*) "Computing magnitude of vector from these files: "
    write(*,*) trim(adjustl(fname_ux))
    write(*,*) trim(adjustl(fname_uy))
    write(*,*) trim(adjustl(fname_uz))
    write(*,*) "Outfile="//trim(adjustl(outfile))
  endif

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))

  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  work = dsqrt( u(:,:,:,1)**2 + u(:,:,:,2)**2 + u(:,:,:,3)**2 )
  deallocate( u )

  call save_field_hdf5 ( time, outfile, work )
  if (mpirank==0) write(*,*) "Wrote magnitude to "//trim(outfile)

  deallocate (work)
  call fft_free()

end subroutine magnitude_post



!-------------------------------------------------------------------------------
! ./flusi -p --energy ux_00.h5 uy_00.h5 uz_00.h5 outfile_00.h5
!-------------------------------------------------------------------------------
! load the vector components from file and compute & save the energy to
! another HDF5 file. (energy = (ux^2+uy^2+uz^2)/2)
subroutine energy_post(help)
  use vars
  use basic_operators
  use p3dfft_wrapper
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, outfile
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr),dimension(:,:,:),allocatable :: work
  real(kind=pr) :: time


  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --energy ux_00.h5 uy_00.h5 uz_00.h5 outfile_00.h5"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! load the vector components from file and compute & save the energy to"
    write(*,*) "! another HDF5 file. (energy = (ux^2+uy^2+uz^2)/2)"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,outfile)

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  if (mpirank==0) write(*,*) "Computing energy of vector from these files: "
  if (mpirank==0) write(*,*) trim(adjustl(fname_ux))//" "//trim(adjustl(fname_uy))//" "//trim(adjustl(fname_uz))
  if (mpirank==0) write(*,*) "Outfile="//trim(adjustl(outfile))

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))

  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  work = 0.5d0 * ( u(:,:,:,1)**2 + u(:,:,:,2)**2 + u(:,:,:,3)**2 )

  call save_field_hdf5 ( time, outfile, work )
  if (mpirank==0) write(*,*) "Wrote energy to "//trim(outfile)

  deallocate (u,work)
  call fft_free()

end subroutine energy_post


!-------------------------------------------------------------------------------
! ./flusi -p --simple-field-operation field1.h5 OP field2.h5 output.h5
!-------------------------------------------------------------------------------
! load two fields and perform a simple operation ( + - / * )
! example: ./flusi -p --simple-field-operation vorabs_0000.h5 * mask_0000.h5 vor2_0000.h5
! this gives just the product vor*mask
subroutine simple_field_operation(help)
  use vars
  use basic_operators
  use p3dfft_wrapper
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: file1, file2, file_out, operation
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr) :: time

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --simple-field-operation field1.h5 OP field2.h5 output.h5"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! load two fields and perform a simple operation ( + - / * )"
    write(*,*) "! example: ./flusi -p --simple-field-operation vorabs_0000.h5 * mask_0000.h5 vor2_0000.h5"
    write(*,*) "! this gives just the product vor*mask"
    write(*,*) "! NOTE: USE AN ESCAPE CHARACTER FOR OPERATION!"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif

  call get_command_argument(3,file1)
  call get_command_argument(4,operation)
  call get_command_argument(5,file2)
  call get_command_argument(6,file_out)


  call check_file_exists( file1 )
  call check_file_exists( file2 )

  if (mpirank==0) write(*,*) "Performing simple operation using the fields"
  if (mpirank==0) write(*,*) trim(adjustl(file1))//" "//trim(adjustl(file2))
  if (mpirank==0) write(*,*) "Operation="//trim(adjustl(operation))
  if (mpirank==0) write(*,*) "Outfile="//trim(adjustl(file_out))

  call fetch_attributes( file1, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))

  call read_single_file ( file1, u(:,:,:,1) )
  call read_single_file ( file2, u(:,:,:,2) )

  select case (operation)
  case ("*")
    if(mpirank==0) write(*,*) "multiplication"
    u(:,:,:,3) = u(:,:,:,1) * u(:,:,:,2)
  case ("/")
    if(mpirank==0) write(*,*) "division"
    u(:,:,:,3) = u(:,:,:,1) / u(:,:,:,2)
  case ("+")
    if(mpirank==0) write(*,*) "addition"
    u(:,:,:,3) = u(:,:,:,1) + u(:,:,:,2)
  case ("-")
    if(mpirank==0) write(*,*) "substraction"
    u(:,:,:,3) = u(:,:,:,1) - u(:,:,:,2)
  case default
    write(*,*) "error operation not supported::"//operation
  end select

  call save_field_hdf5 ( time, file_out, u(:,:,:,3) )

  if (mpirank==0) write(*,*) "Wrote result to "//trim(file_out)

  deallocate (u)
  call fft_free()

end subroutine simple_field_operation



!-------------------------------------------------------------------------------
! ./flusi --postprocess --check-params-file PARAMS.ini
!-------------------------------------------------------------------------------
! load a parameter file and check for a bunch of common mistakes/typos
! you tend to make, in order to help preventing stupid mistakes
subroutine check_params_file(help)
  use fsi_vars
  use solid_model
  use insect_module
  use helpers
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: infile
  type(diptera) :: Insect

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p  --check-params-file PARAMS.ini"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) ""
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  method="fsi"
  nf = 1
  nd = 3
  allocate(lin(1))

  call get_command_argument(3,infile)
  call check_file_exists(infile)
  call get_params(infile,Insect)

  ! now we have the parameters and perform the tests
  if ((dx /= dy).or.(dx /= dz).or.(dz /=dy)) then
    write(*,*) "The resolution is NOT equidistant ", dx,dy,dz
  endif

  if (iMask=="insect") then
    if ((Insect%BodyMotion=="free_flight").and.(iTimeMethodFluid/="AB2_rigid_solid")) then
      write(*,*) "Insect%BodyMotion==free_flight but iTimeMethodFluid="//trim(adjustl(iTimeMethodFluid))
    endif
  endif

  if ((method=="fsi").and.(use_slicing=="yes")) then
    if (maxval(slices_to_save)>nx-1) then
      write(*,*) "Slicing is ON but at least one index is out of bounds: ", slices_to_save
    endif
  endif

  if ((use_solid_model=="yes").and.(iMask /= "Flexibility")) then
    write(*,*) "we use the solid model but the mask is wrongly set"
  endif

  write(*,'("Penalization parameter C_eta=",es12.4," and K_eta=",es12.4)') eps, &
  sqrt(nu*eps)/dx

  write(*,'("This simulation will produce ",f5.1,"GB HDD output, if it runs until the end")') &
  dble(iSaveVelocity*3+iSavePress+iSaveVorticity*3+iSaveMask+iSaveSolidVelocity*3) &
  *((dble(nx)*dble(ny)*dble(nz))*4.d0/1000.d0**3)*tmax/tsave &
  +dble(iDoBackup*2)*18.d0*((dble(nx)*dble(ny)*dble(nz))*4.d0/1000.d0**3)*2.d0 !two backup files à 18 fields double precision each.


end subroutine



!-------------------------------------------------------------------------------
! ./flusi -p --field-analysis ux_00000.h5 uy_00000.h5 uz_00000.h5 outfile.dat
!-------------------------------------------------------------------------------
subroutine field_analysis(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, outfile
  complex(kind=pr),dimension(:,:,:,:),allocatable :: uk
  real(kind=pr),dimension(:,:,:,:),allocatable :: u
  real(kind=pr) :: time, epsilon_loc, epsilon, fact, E, u_rms,lambda_macro,lambda_micro
  integer :: ix,iy,iz, mpicode
  real(kind=pr) :: Z_loc,Z_tot,nu2

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --field-analysis ux_00000.h5 uy_00000.h5 uz_00000.h5 outfile.dat"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "FLUSI field analysis. From a given vector field u (three files, one for each component)"
    write(*,*) "we'll compute the kinetic energy E=(ux^2 + uy^2 + uz^2)/2, then the curl vor = curl(u)"
    write(*,*) "and the enstrophy Z=(vorx^2 + vory^2 + vorz^2)/2 as well as the dissipation rate "
    write(*,*) "epsilon=nu*Z, where the viscosity is read from the files. (note you might have to add it"
    write(*,*) "using --set-hdf5-attribute to the file if it is missing) We print the output (integral "
    write(*,*) "and mean) to an ascii file given in the call, as well as on the screen"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif

  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,outfile)

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  if (mpirank==0) then
  if ((fname_ux(1:2).ne."ux").or.(fname_uy(1:2).ne."uy").or.(fname_uz(1:2).ne."uz")) then
    write (*,*) "Warning in arguments, files do not start with ux uy and uz"
    write (*,*) "note files have to be in the right order"
  endif
  endif

  if(mpirank==0) then
    write(*,*) " OUTPUT will be written to "//trim(adjustl(outfile))
    open(17,file=trim(adjustl(outfile)),status='replace')
    call postprocessing_ascii_header(17)
    write(17,'(A)') "-----------------------------------"
    write(17,'(A)') "FLUSI field analysis"
    write(17,'(A)') "-----------------------------------"
  endif

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)

  call fft_initialize() ! also initializes the domain decomp
  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))

  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )

  ! field energy
  epsilon_loc = 0.5d0*sum(u(:,:,:,1)**2+u(:,:,:,2)**2+u(:,:,:,3)**2)*(dx*dy*dz)
  call MPI_REDUCE(epsilon_loc,E,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)

  ! compute vorticity
  if (mpirank==0) write(*,*) "Computing vorticity.."
  call fft3 (inx=u,outk=uk)
  call curl3_inplace (uk)
  call ifft3 (ink=uk,outx=u)

  ! compute enstrophy
  Z_loc = 0.5d0*sum(u(:,:,:,1)**2+u(:,:,:,2)**2+u(:,:,:,3)**2)*(dx*dy*dz)
  call MPI_REDUCE(Z_loc,Z_tot,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)

  if(mpirank==0) then
    write(*,'("viscosity=",es15.8)') nu
    write(*,'("Total kinetic energy =",es15.8)') E
    write(*,'("Total Enstrophy =",es15.8)') Z_tot
    write(*,'("Total Dissipation =",es15.8)') nu*Z_tot
    write(*,'("Mean kinetic energy =",es15.8)') E / (xl*yl*zl)
    write(*,'("Mean Enstrophy =",es15.8)') Z_tot / (xl*yl*zl)
    write(*,'("Mean Dissipation =",es15.8)') nu*Z_tot / (xl*yl*zl)

    write(17,'("viscosity=",es15.8)') nu
    write(17,'("Total kinetic energy =",es15.8)') E
    write(17,'("Total Enstrophy =",es15.8)') Z_tot
    write(17,'("Total Dissipation =",es15.8)') nu*Z_tot
    write(17,'("Mean kinetic energy =",es15.8)') E / (xl*yl*zl)
    write(17,'("Mean Enstrophy =",es15.8)') Z_tot / (xl*yl*zl)
    write(17,'("Mean Dissipation =",es15.8)') nu*Z_tot / (xl*yl*zl)
  endif

  deallocate (u,uk)
  call fft_free()
end subroutine field_analysis



!-------------------------------------------------------------------------------
! compute helicity from velocity field with spectral accuracy
!
!-------------------------------------------------------------------------------
subroutine post_helicity(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use helpers
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: fname_ux, fname_uy, fname_uz, outfile, normalized
  complex(kind=pr),dimension(:,:,:,:),allocatable :: uk
  real(kind=pr),dimension(:,:,:,:),allocatable :: u, vor
  real(kind=pr),dimension(:,:,:),allocatable :: work
  real(kind=pr) :: time, divu_max, errx, erry, errz
  integer :: ix,iy,iz, mpicode

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --helicity ux_000.h5 uy_000.h5 uz_000.h5 helicity_000.h5 [--normalized]"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "! compute (normalized) helicity from given velocity field"
    write(*,*) "! employs spectral precision"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif


  !-----------------------------------------------------------------------------
  ! Initializations
  !-----------------------------------------------------------------------------
  call get_command_argument(3,fname_ux)
  call get_command_argument(4,fname_uy)
  call get_command_argument(5,fname_uz)
  call get_command_argument(6,outfile)
  call get_command_argument(7,normalized)


  ! header and information
  if (mpirank==0) then
    write(*,'(80("-"))')
    write(*,*) "helicity computation"
    write(*,*) "Computing helicit from velocity given in these files: "
    write(*,'(80("-"))')
    write(*,*) trim(adjustl(fname_ux))
    write(*,*) trim(adjustl(fname_uy))
    write(*,*) trim(adjustl(fname_uz))
    write(*,*) "Writing to:"
    write(*,*) trim(adjustl(outfile))
    write(*,'(80("-"))')
  endif

  call check_file_exists( fname_ux )
  call check_file_exists( fname_uy )
  call check_file_exists( fname_uz )

  call fetch_attributes( fname_ux, nx, ny, nz, xl, yl, zl, time, nu )

  pi = 4.d0 *datan(1.d0)
  scalex = 2.d0*pi/xl
  scaley = 2.d0*pi/yl
  scalez = 2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)
  neq=3
  nd=3
  ncw=3
  nrw=3

  call fft_initialize() ! also initializes the domain decomp

  allocate(u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(vor(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3))
  allocate(work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3))

  ! read vorticity from files to u
  call read_single_file ( fname_ux, u(:,:,:,1) )
  call read_single_file ( fname_uy, u(:,:,:,2) )
  call read_single_file ( fname_uz, u(:,:,:,3) )


  call fft3( inx=u,outk=uk )
  call curl( uk )
  call ifft3( ink=uk, outx=vor )

  if (normalized == "--normalized" ) then
    if (mpirank==0) write(*,*) "computing normalized helicity"
    call helicity_norm( u, vor, work)
  else
    if (mpirank==0) write(*,*) "computing absolute helicity"
    call helicity( u, vor, work)
  endif

  ! now u contains the velocity in physical space
  call save_field_hdf5 ( time, outfile, work )

  deallocate (u,uk,vor,work)
  call fft_free()
end subroutine post_helicity



!-------------------------------------------------------------------------------
!./flusi -p --smooth-inverse-mask mask_000.h5 smooth_000.h5
!-------------------------------------------------------------------------------
subroutine post_smooth_mask(help)
  use vars
  use p3dfft_wrapper
  use basic_operators
  use ini_files_parser
  use mpi
  implicit none
  logical, intent(in) :: help
  character(len=strlen) :: infile, outfile
  complex(kind=pr),dimension(:,:,:),allocatable :: uk,rhs
  real(kind=pr),dimension(:,:,:),allocatable :: u1,u2,tmp
  real(kind=pr),dimension(:,:,:,:),allocatable :: expvis
  real(kind=pr) :: time, dt
  integer :: mpicode, it
  type(inifile) :: params

  if (help.and.root) then
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "./flusi -p --smooth-inverse-mask mask_000.h5 smooth_000.h5"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Reads in the mask function and solves the penalized heat equation, i.e. it diffuses the"
    write(*,*) "mask while trying to keep 1 inside the solid. then, we save (1-mask) to disk, so that "
    write(*,*) "one can multiply a field with it in order to smoothly cut out the region near the "
    write(*,*) "penalized domain. The equation is:"
    write(*,*) " d chi / dt = nu*laplace(chi) - (chi0/eta)*(chi-1.0)"
    write(*,*) " where chi is the dilluted mask and chi0 is the initial mask (sharpened)"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "The code reads in a small smoothing.ini file which contains the required parameters"
    write(*,*) "contents of this file:"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "[smoothing]"
    write(*,*) "nu=1.0e-1; viscosity"
    write(*,*) "eps=1e-2; penalization"
    write(*,*) "tmax=0.2; final time"
    write(*,*) "dt=0.95e-2; time step"
    write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    write(*,*) "Parallel: yes"
    return
  endif

  call get_command_argument(3,infile)
  call get_command_argument(4,outfile)

  call check_file_exists( infile )
  call fetch_attributes( infile, nx, ny, nz, xl, yl, zl, time, nu )

  pi=4.d0 *datan(1.d0)
  scalex=2.d0*pi/xl
  scaley=2.d0*pi/yl
  scalez=2.d0*pi/zl
  dx = xl/dble(nx)
  dy = yl/dble(ny)
  dz = zl/dble(nz)
  nf = 1

  ! read in parameters
  if (root) call read_ini_file( params, "smoothing.ini", .true.)
  call read_param( params,"smoothing","nu",nu,1.0d-1 )
  call read_param( params,"smoothing","eps",eps,1.0d-2 )
  call read_param( params,"smoothing","dt",dt,0.5d-2 )
  call read_param( params,"smoothing","tmax",tmax,1.d0 )
  if (root) call clean_ini_file( params )

  allocate(lin(1))
  lin(1) = nu

  call fft_initialize() ! also initializes the domain decomp

  allocate(u1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))
  allocate(u2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))
  allocate(tmp(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)))
  allocate(uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3)))
  allocate(rhs(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3)))
  allocate(expvis(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nf))

  call read_single_file ( infile, u1 )

  !-----------------------------------------------------------------------------
  ! we use u2 for forcing:
  u2 = u1
  if (root) write(*,*) "Removing smoothing layer from source term..."
  ! wherever the mask is present, we will force to one, in order to exclude the
  ! smoothing layer. That way, we are hopeful that the resulting function will be
  ! zero at the first onset on smoothing
  where (u2>1.0d-10)
    u2 = 1.d0
  end where

  !-----------------------------------------------------------------------------
  ! the initial condition is what we read from file (stepping in Fourier space)
  call fft ( inx=u1, outk=uk )

  ! compute number of time steps (approx.) to reach tmax from ini file
  nt = nint(tmax/dt)
  if (root) then
    write(*,*) "nt=",nt
    write(*,'("Penalization parameter C_eta=",es12.4," and K_eta=",es12.4)') eps, &
    sqrt(nu*eps)/dx
  endif

  ! compute integrating factor for diffusive term
  call cal_vis( dt, expvis )

  !-----------------------------------------------------------------------------
  ! loop over time steps for penalized heat equation problem
  !-----------------------------------------------------------------------------
  do it=1, nt
      if (root) then
        write(*,*) "step",it,"of",nt
      endif

      ! this is the penalization term:
      tmp = -u2/eps*(u1-1.d0)
      ! to Fourier space
      call fft( inx=tmp, outk=rhs )
      ! advance in time (euler), viscosity is treated with integrating factor:
      uk = (uk + dt*rhs)*expvis(:,:,:,1)
      ! for the next time step we need phys. space to compute penalization term
      call ifft ( ink=uk, outx=u1)
  enddo

  ! save inverse of smoothed mask to disk
  tmp = 1.d0 - u1
  call save_field_hdf5 ( time, outfile, tmp )

  ! done
  deallocate (u1,u2,uk,expvis,rhs,tmp)
  call fft_free()

end subroutine post_smooth_mask
