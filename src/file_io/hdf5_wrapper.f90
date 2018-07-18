module hdf5_wrapper

  use mpi
  use vars, only : pr, root, field_precision, mpirank
  use hdf5
  implicit none

  ! interface for writing attributes. an attribute is an object which is attached
  ! to a dataset, in our case a array saved in the file. we put useful information
  ! in attributes, for example the time, resolution and domain size
  ! both routines take vector values input
  interface write_attribute
    module procedure write_attrib_dble, write_attrib_int
  end interface

  ! we can also read attributes from existing files and datasets. thus, for example
  ! when reading a field from file, we check the attribute nxyz for the size,
  ! so we know how much memory to allocate
  interface read_attribute
    module procedure read_attrib_dble, read_attrib_int
  end interface

contains


!-------------------------------------------------------------------------------
! Read a field from a file
! Note a single file can contain many arrays, if required
! INPUT
!   filename        file to read from
!   dsetname        datasetname, i.e. the name of the array in the file
!   lbounds           lower bounds of memory portion hold by the CPU
!   ubounds           upper bounds of memory portion hold by the CPU
!                   NOTE: lbounds and ubounds are 1:3 arrays. if running on one proc
!                   they are lbounds=(/0,0,0/) ubounds=(/nx-1,ny-1,nz-1/). If the data
!                   is distributed among procs, each proc has to indicate which
!                   portion of the array it holds
!   field           actual data (ALLOCATED!!!)
! OUTPUT:
!   field           data read from file
!-------------------------------------------------------------------------------
subroutine read_field_hdf5 ( filename, dsetname, lbounds, ubounds, field )
  implicit none

  character(len=*),intent(in) :: filename, dsetname
  integer,dimension(1:3), intent(in) :: lbounds, ubounds
  real(kind=pr),intent(inout) :: field(lbounds(1):ubounds(1),lbounds(2):ubounds(2),lbounds(3):ubounds(3))

  integer, parameter            :: rank = 3 ! data dimensionality (2D or 3D)
  integer                       :: i

  integer(hid_t) :: file_id       ! file identifier
  integer(hid_t) :: dset_id       ! dataset identifier
  integer(hid_t) :: filespace     ! dataspace identifier in file
  integer(hid_t) :: memspace      ! dataspace identifier in memory
  integer(hid_t) :: plist_id      ! property list identifier

  integer(hsize_t), dimension(rank) :: dims_global
  integer(hsize_t), dimension(rank) :: dims_file, dims_dummy
  integer(hsize_t), dimension(rank) :: dims_local
  integer(hsize_t), dimension(rank) :: chunk_dims  ! chunks dimensions

  integer(hsize_t),  dimension(rank) :: count  = 1
  integer(hssize_t), dimension(rank) :: offset
  integer(hsize_t),  dimension(rank) :: stride = 1
  integer :: error,mpicode,mindim,maxdim  ! error flags

  ! what follows is for the attribute "time"
  integer, parameter :: arank = 1

  ! determine size of memory (i.e. the entire array).
  call MPI_ALLREDUCE ( lbounds(1), mindim,1,MPI_INTEGER,MPI_MIN,MPI_COMM_WORLD,mpicode)
  call MPI_ALLREDUCE ( ubounds(1), maxdim,1,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,mpicode)
  dims_global(1) = int( maxdim-mindim+1, kind=hsize_t)

  call MPI_ALLREDUCE ( lbounds(2), mindim,1,MPI_INTEGER,MPI_MIN,MPI_COMM_WORLD,mpicode)
  call MPI_ALLREDUCE ( ubounds(2), maxdim,1,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,mpicode)
  dims_global(2) = int( maxdim-mindim+1, kind=hsize_t)

  call MPI_ALLREDUCE ( lbounds(3), mindim,1,MPI_INTEGER,MPI_MIN,MPI_COMM_WORLD,mpicode)
  call MPI_ALLREDUCE ( ubounds(3), maxdim,1,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,mpicode)
  dims_global(3) = int( maxdim-mindim+1, kind=hsize_t)

  !-----------------------------------------------------------------------------
  ! load the file
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
  call h5fopen_f (filename, H5F_ACC_RDWR_F, file_id, error, plist_id)
  ! this closes the property list (we'll re-use it)
  call h5pclose_f(plist_id, error)

  ! Definition of memory distribution
  dims_local(1) = ubounds(1)-lbounds(1) +1
  dims_local(2) = ubounds(2)-lbounds(2) +1
  dims_local(3) = ubounds(3)-lbounds(3) +1

  offset(1) = lbounds(1)
  offset(2) = lbounds(2)
  offset(3) = lbounds(3)

  !----------------------------------------------------------------------------
  ! Read actual field from file (dataset)
  !----------------------------------------------------------------------------
  ! dataspace in the file: contains all data from all procs
  call h5screate_simple_f(rank, dims_global, filespace, error)
  ! dataspace in memory: contains only local data
  call h5screate_simple_f(rank, dims_local, memspace, error)

  ! Create chunked dataset
  call h5pcreate_f(H5P_DATASET_CREATE_F, plist_id, error)

  ! Open an existing dataset.
  call h5dopen_f(file_id, dsetname, dset_id, error)
  ! get its dataspace
  call h5dget_space_f(dset_id, filespace, error)
  ! get the dimensions of the field in the file
  call h5sget_simple_extent_dims_f(filespace, dims_file, dims_dummy, error)

  if ( (dims_global(1)/=dims_file(1)).or.(dims_global(2)/=dims_file(2)).or.(dims_global(3)/=dims_file(3)) ) then
    if (root) then
      write(*,'(80("w"))')
      write(*,'(A)') "WARNING read_field_hdf5: the dimension of the data in the file"
      write(*,'(A)') "        and the global array definition do not match. This can cause a"
      write(*,'(A)') "        problem if you try to read inexistent data, but for subsets its fine."
      write(*,'("        in file: ",3(i5,1x)," in params: ",3(i5,1x))') dims_file, dims_global
      write(*,'(80("w"))')
    endif
  endif

  ! Select hyperslab in the file.
  call h5sselect_hyperslab_f (filespace, H5S_SELECT_SET_F, offset, count, &
  error, stride, dims_local)

  ! Create property list for collective dataset read
  call h5pcreate_f(H5P_DATASET_XFER_F, plist_id, error)
  call h5pset_dxpl_mpio_f(plist_id, H5FD_MPIO_COLLECTIVE_F, error)


  call h5dread_f( dset_id, H5T_NATIVE_DOUBLE, field, dims_local, error, &
  mem_space_id = memspace, file_space_id = filespace, xfer_prp = plist_id )

  call h5sclose_f(filespace, error)
  call h5sclose_f(memspace, error)
  call h5pclose_f(plist_id, error) ! note the dataset remains opened

  ! Close dataset
  call h5dclose_f(dset_id, error)
  call h5fclose_f(file_id,error)
  call H5close_f(error)

end subroutine read_field_hdf5

!-------------------------------------------------------------------------------
! write array to HDF5 file
! Note a single file can contain many arrays, if required
! INPUT
!   filename        file to write to
!   dsetname        datasetname, i.e. the name of the array in the file
!   lbounds           lower bounds of memory portion hold by the CPU
!   ubounds           upper bounds of memory portion hold by the CPU
!                   NOTE: lbounds and ubounds are 1:3 arrays. if running on one proc
!                   they are lbounds=(/0,0,0/) ubounds=(/nx-1,ny-1,nz-1/). If the data
!                   is distributed among procs, each proc has to indicate which
!                   portion of the array it holds
!   field       actual data
!   overwrite       (optional) if .false., an existing file will not be erased and
!                   instead we just add the array to this file. Default is .true.
!                   NOTE: an error occurs if the dataset already exists, as hdf5
!                   does not provide a possibility to erase something already there
! OUTPUT:
!   none
!-------------------------------------------------------------------------------
subroutine write_field_hdf5( filename, dsetname, lbounds, ubounds, field, overwrite)
  implicit none

  character(len=*), intent (in) :: filename, dsetname
  integer,dimension(1:3), intent(in) :: lbounds, ubounds
  real(kind=pr),intent(in) :: field(lbounds(1):ubounds(1),lbounds(2):ubounds(2),lbounds(3):ubounds(3))
  logical, intent(in), optional :: overwrite

  integer, parameter :: rank = 3 ! data dimensionality (2D or 3D)
  integer(hid_t) :: file_id   ! file identifier
  integer(hid_t) :: dset_id   ! dataset identifier
  integer(hid_t) :: filespace ! dataspace identifier in file
  integer(hid_t) :: memspace  ! dataspace identifier in memory
  integer(hid_t) :: plist_id  ! property list identifier
  integer(hid_t) :: file_precision

  ! dataset dimensions in the file.
  integer(hsize_t), dimension(rank) :: dims_global
  ! hyperslab dimensions
  integer(hsize_t), dimension(rank) :: dims_local
  ! chunk dimensions
  integer(hsize_t), dimension(rank) :: chunk_dims
  ! how many blocks to select from dataspace
  integer(hsize_t),  dimension(rank) :: count  = 1
  integer(hssize_t), dimension(rank) :: offset
  ! stride is spacing between elements, this is one here. striding is done in the
  ! caller; here, we just write the entire (possibly downsampled) field to disk.
  integer(hsize_t),  dimension(rank) :: stride = 1
  integer :: error  ! error flags

  ! HDF attribute variables
  integer, parameter :: arank = 1
  integer(hsize_t), DIMENSION(1) :: adims  ! Attribute dimension

  integer :: i, mindim, maxdim, mpicode
  logical :: exist1, ovrwrte

  if (present(overwrite)) then
    ovrwrte = overwrite
  else
    ! default is erase file and re-create it
    ovrwrte = .true.
  endif

  ! ----------------------------------------------------------------------------
  ! Compute the dimension of the complete field (i.e. the union of all CPU's)
  ! which we will write to file.
  ! ----------------------------------------------------------------------------
  call MPI_ALLREDUCE ( lbounds(1),mindim,1,MPI_INTEGER,MPI_MIN,MPI_COMM_WORLD,mpicode)
  call MPI_ALLREDUCE ( ubounds(1),maxdim,1,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,mpicode)
  dims_global(1) = int( maxdim-mindim+1, kind=hsize_t )

  call MPI_ALLREDUCE ( lbounds(2),mindim,1,MPI_INTEGER,MPI_MIN,MPI_COMM_WORLD,mpicode)
  call MPI_ALLREDUCE ( ubounds(2),maxdim,1,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,mpicode)
  dims_global(2) = int( maxdim-mindim+1, kind=hsize_t )

  call MPI_ALLREDUCE ( lbounds(3),mindim,1,MPI_INTEGER,MPI_MIN,MPI_COMM_WORLD,mpicode)
  call MPI_ALLREDUCE ( ubounds(3),maxdim,1,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,mpicode)
  dims_global(3) = int( maxdim-mindim+1, kind=hsize_t )

  ! Tell HDF5 how our  data is organized:
  offset(1) = lbounds(1)
  offset(2) = lbounds(2)
  offset(3) = lbounds(3)
  dims_local(1) = ubounds(1)-lbounds(1) + 1
  dims_local(2) = ubounds(2)-lbounds(2) + 1
  dims_local(3) = ubounds(3)-lbounds(3) + 1


  ! Initialize HDF5 library and Fortran interfaces.
  call h5open_f(error)
  ! Setup file access property list with parallel I/O access.
  ! this sets up a property list (plist_id) with standard values for
  ! FILE_ACCESS
  call h5pcreate_f(H5P_FILE_ACCESS_F, plist_id, error)
  ! Modify the property list and store the MPI IO comminucator
  ! information in the file access property list
  call h5pset_fapl_mpio_f(plist_id, MPI_COMM_WORLD, MPI_INFO_NULL, error)


  !-----------------------------------------------------------------------------
  ! open the file
  !-----------------------------------------------------------------------------
  ! check if the file already exists
  inquire ( file=filename, exist=exist1 )
  if ((exist1 .eqv. .false. ) .or. (ovrwrte .eqv. .true.) ) then
    ! file does not exist, create the file collectively
    call h5fcreate_f(trim(adjustl(filename)), H5F_ACC_TRUNC_F, file_id, error, access_prp = plist_id)
  else
    ! file does exist, open it. if the dataset we want to write exists already
    ! it will be overwritten. however, if other datasets are present, they will not
    ! be erased
    call h5fopen_f(trim(adjustl(filename)), H5F_ACC_RDWR_F , file_id, error, access_prp = plist_id)
  endif

  ! this closes the property list plist_id (we'll re-use it)
  call h5pclose_f(plist_id, error)

  !-----------------------------------------------------------------------------
  ! create dataspace "filespace" to write to
  !-----------------------------------------------------------------------------
  ! Create the data space for the  dataset.
  ! Dataspace in the file: contains all data from all procs
  call h5screate_simple_f(rank, dims_global, filespace, error)

  ! Create chunked dataset.
  call h5pcreate_f(H5P_DATASET_CREATE_F, plist_id, error)

  ! determine what precision to use when writing to disk
  if (field_precision=="double") then
    ! Output files in double precision
    file_precision = H5T_NATIVE_DOUBLE
  else
    ! Output files in single precision
    file_precision = H5T_NATIVE_REAL
  endif

  ! check if the dataset already exists
  call h5lexists_f(file_id, dsetname, exist1, error)
  if (exist1) then
    write(*,*) "You are trying to write to an existing dataset...this is not supported."
    call MPI_ABORT(MPI_COMM_WORLD,4441,mpicode)
  endif

  ! create the dataset
  call h5dcreate_f(file_id, dsetname, file_precision, filespace, dset_id, error, plist_id)
  call h5sclose_f(filespace, error)

  ! Select hyperslab in the file.
  call h5dget_space_f(dset_id, filespace, error)
  call h5sselect_hyperslab_f (filespace, H5S_SELECT_SET_F, offset, count, &
  error, stride, dims_local)

  ! Create property list for collective dataset write
  call h5pcreate_f(H5P_DATASET_XFER_F, plist_id, error)
  call h5pset_dxpl_mpio_f(plist_id, H5FD_MPIO_INDEPENDENT_F, error)
  !-----------------------------------------------------------------------------
  ! create dataspace "memspace" to be written
  !-----------------------------------------------------------------------------
  ! dataspace in memory: contains only local data
  call h5screate_simple_f(rank, dims_local, memspace, error)

  !-----------------------------------------------------------------------------
  ! actual writing of heavy data
  !-----------------------------------------------------------------------------
  ! Write the dataset collectively, double precision in memory
  call h5dwrite_f(dset_id, H5T_NATIVE_DOUBLE, field, dims_global, &
  error, file_space_id = filespace, mem_space_id = memspace,xfer_prp = plist_id)

  !!! Close dataspaces:
  call h5sclose_f(filespace, error)
  call h5sclose_f(memspace, error)
  call h5dclose_f(dset_id, error) ! Close the dataset.
  call h5pclose_f(plist_id, error) ! Close the property list.
  call h5fclose_f(file_id, error) ! Close the file.
  call h5close_f(error) ! Close Fortran interfaces and HDF5 library.
end subroutine write_field_hdf5



!-------------------------------------------------------------------------------
! write an attribute
! INPUT:
!   filename  what file to write to (e.g. hallo.h5)
!   dsetname  what dataset to write to (e.g. stuff to append to hallo.h5:stuff)
!   aname     the name of the attribute to write
!   attribute the vector that will hold the attribute. note: this routine uses
!             assumed shaped arrays: it will try to read as many values as the size of the vectors
! OUTPUT:
!   none
!-------------------------------------------------------------------------------
subroutine write_attrib_dble(filename,dsetname,aname,attribute)
  implicit none

  character(len=*), intent (in) :: filename, dsetname, aname
  real(kind=pr), DIMENSION(:), intent (in) :: attribute

  integer, parameter :: arank = 1
  integer :: dim
  integer :: error  ! error flags
  integer(hid_t) :: aspace_id ! Attribute Dataspace identifier
  integer(hid_t) :: attr_id   ! Attribute identifier
  integer(hid_t) :: file_id
  integer(hid_t) :: dset_id  ! dataset identifier
  integer(hsize_t) :: adims(1)  ! Attribute dimension
  logical :: exists

  if (root.eqv..false.) return

  ! convert input data for the attribute to the precision required by the HDF library
  dim = size(attribute)
  adims = int(dim, kind=hsize_t)

  ! Initialize HDF5 library and Fortran interfaces.
  call h5open_f(error)

  ! open the file (existing file)
  call h5fopen_f(filename, H5F_ACC_RDWR_F, file_id, error )

  ! open the dataset
  call h5dopen_f(file_id, dsetname, dset_id, error)

  ! check if attribute exists already
  call h5aexists_f(dset_id, aname, exists, error)

  if (exists) then
    ! open attribute (it exists already)
    call h5aopen_f(dset_id, aname, attr_id, error)
    ! Get dataspace
    call h5aget_space_f(attr_id, aspace_id, error)
    ! Write the attribute data attribute to the attribute identifier attr_id.
    call h5awrite_f(attr_id, H5T_NATIVE_DOUBLE, attribute, adims, error)
  else
    ! Determine the dataspace identifier aspace_id
    call h5screate_simple_f(arank,adims,aspace_id,error)
    ! set attr_id, ie create an attribute attached to the object dset_id
    call h5acreate_f(dset_id,aname,H5T_NATIVE_DOUBLE,aspace_id,attr_id,error)
    ! Write the attribute data attribute to the attribute identifier attr_id.
    call h5awrite_f(attr_id,H5T_NATIVE_DOUBLE,attribute,adims,error)
  endif

  call h5aclose_f(attr_id,error) ! Close the attribute.
  call h5sclose_f(aspace_id,error) ! Terminate access to the data space.
  call h5dclose_f(dset_id,error)
  call h5fclose_f(file_id,error)
  call h5close_f(error) ! Close Fortran interfaces and HDF5 library.
end subroutine write_attrib_dble


!-------------------------------------------------------------------------------
! write an attribute
! INPUT:
!   filename  what file to write to (e.g. hallo.h5)
!   dsetname  what dataset to write to (e.g. stuff to append to hallo.h5:stuff)
!   aname     the name of the attribute to write
!   attribute the vector that will hold the attribute. note: this routine uses
!             assumed shaped arrays: it will try to read as many values as the size of the vectors
! OUTPUT:
!   none
!-------------------------------------------------------------------------------
subroutine write_attrib_int(filename,dsetname,aname,attribute)
  implicit none

  character(len=*), intent (in) :: filename, dsetname, aname
  integer, DIMENSION(:), intent (in) :: attribute

  integer(hsize_t) :: adims(1)  ! Attribute dimension
  integer, parameter :: arank = 1
  integer :: dim
  integer :: error  ! error flags
  integer(hid_t) :: aspace_id ! Attribute Dataspace identifier
  integer(hid_t) :: attr_id   ! Attribute identifier
  integer(hid_t) :: file_id
  integer(hid_t) :: dset_id  ! dataset identifier
  logical :: exists

  ! only the root rank writes the attribute
  if (root.eqv..false.) return

  ! convert input data for the attribute to the precision required by the HDF library
  dim = size(attribute)
  adims = int(dim, kind=hsize_t)

  ! Initialize HDF5 library and Fortran interfaces.
  call h5open_f(error)

  ! open the file (existing file)
  call h5fopen_f(filename, H5F_ACC_RDWR_F, file_id, error )

  ! open the dataset
  call h5dopen_f(file_id, dsetname, dset_id, error)

  ! check if attribute exists already
  call h5aexists_f(dset_id, aname, exists, error)

  if (exists) then
    ! open attribute (it exists already)
    call h5aopen_f(dset_id, aname, attr_id, error)
    ! Get dataspace
    call h5aget_space_f(attr_id, aspace_id, error)
    ! Write the attribute data attribute to the attribute identifier attr_id.
    call h5awrite_f(attr_id, H5T_NATIVE_INTEGER, attribute, adims, error)
  else
    ! Determine the dataspace identifier aspace_id
    call h5screate_simple_f(arank,adims,aspace_id,error)
    ! set attr_id, ie create an attribute attached to the object dset_id
    call h5acreate_f(dset_id,aname,H5T_NATIVE_INTEGER,aspace_id,attr_id,error)
    ! Write the attribute data attribute to the attribute identifier attr_id.
    call h5awrite_f(attr_id,H5T_NATIVE_INTEGER,attribute,adims,error)
  endif

  call h5aclose_f(attr_id,error) ! Close the attribute.
  call h5sclose_f(aspace_id,error) ! Terminate access to the data space.
  call h5dclose_f(dset_id,error)
  call h5fclose_f(file_id,error)
  call h5close_f(error) ! Close Fortran interfaces and HDF5 library.
end subroutine write_attrib_int

!-------------------------------------------------------------------------------
! Read an attribute
! INPUT:
!   filename  what file to read from (e.g. hallo.h5)
!   dsetname  what dataset to read from within the file (e.g. stuff to read hallo.h5:stuff)
!   aname     the name of the attribute to read
!   attribute the vector that will hold the attribute. note: this routine uses
!             assumed shaped arrays: it will try to read as many values as the size of the vectors
! OUTPUT:
!   attribute the values read from file
!-------------------------------------------------------------------------------
subroutine read_attrib_int(filename,dsetname,aname,attribute)
  implicit none

  character(len=*), intent (in) :: filename, dsetname, aname
  integer, DIMENSION(:), intent (inout) :: attribute
  integer, parameter :: arank = 1

  integer :: dim
  integer :: error  ! error flags
  integer(hid_t) :: aspace_id ! Attribute Dataspace identifier
  integer(hid_t) :: attr_id   ! Attribute identifier
  integer(hid_t) :: file_id
  integer(hid_t) :: dset_id  ! dataset identifier
  integer(hsize_t) :: adims(1)  ! Attribute dimension
  logical :: exists

  dim = size(attribute)

  ! only root reads attribute (Thomas, 13.02.2o18, as a consequence of a race-condition
  ! bug in --io-test)
  if (root) then
    ! convert input data for the attribute to the precision required by the HDF library
    adims(1) = int(dim, kind=hsize_t)

    ! Initialize HDF5 library and Fortran interfaces.
    call h5open_f(error)

    ! open the file (existing file)
    call h5fopen_f(filename, H5F_ACC_RDONLY_F, file_id, error )

    ! open the dataset
    call h5dopen_f(file_id, dsetname, dset_id, error)

    ! check if attribute exists
    call h5aexists_f(dset_id, aname, exists, error)

    if (exists) then
      ! open attribute
      call h5aopen_f(dset_id, aname, attr_id, error)
      ! Get dataspace for attribute
      call h5aget_space_f(attr_id, aspace_id, error)
      ! read attribute data
      call h5aread_f( attr_id, H5T_NATIVE_INTEGER, attribute, adims, error)
      ! close attribute
      call h5aclose_f(attr_id,error) ! Close the attribute.
      call h5sclose_f(aspace_id,error) ! Terminate access to the data space.
    else
      attribute = 0
    endif

    call h5dclose_f(dset_id,error)
    call h5fclose_f(file_id,error)
    call h5close_f(error) ! Close Fortran interfaces and HDF5 library.
  endif


  call MPI_BCAST( attribute, dim, MPI_INTEGER, 0, MPI_COMM_WORLD, error )
end subroutine read_attrib_int


!-------------------------------------------------------------------------------
! Read an attribute
! INPUT:
!   filename  what file to read from (e.g. hallo.h5)
!   dsetname  what dataset to read from within the file (e.g. stuff to read hallo.h5:stuff)
!   aname     the name of the attribute to read
!   attribute the vector that will hold the attribute. note: this routine uses
!             assumed shaped arrays: it will try to read as many values as the size of the vectors
! OUTPUT:
!   attribute the values read from file
!-------------------------------------------------------------------------------
subroutine read_attrib_dble(filename,dsetname,aname,attribute)
  implicit none

  character(len=*), intent (in) :: filename, dsetname
  real(kind=pr), DIMENSION(:), intent (inout) :: attribute
  character(len=*), intent(in) :: aname ! attribute name
  integer, parameter :: arank = 1

  integer :: dim
  integer :: error  ! error flags
  integer(hid_t) :: aspace_id ! Attribute Dataspace identifier
  integer(hid_t) :: attr_id   ! Attribute identifier
  integer(hid_t) :: file_id
  integer(hid_t) :: dset_id  ! dataset identifier
  integer(hsize_t) :: adims(1)  ! Attribute dimension
  logical :: exists

  ! convert input data for the attribute to the precision required by the HDF library
  dim = size(attribute)

  if (root) then
    adims(1) = int(dim, kind=hsize_t)

    ! Initialize HDF5 library and Fortran interfaces.
    call h5open_f(error)

    ! open the file (existing file)
    call h5fopen_f(filename, H5F_ACC_RDONLY_F, file_id, error )

    ! open the dataset
    call h5dopen_f(file_id, dsetname, dset_id, error)

    ! check if attribute exists
    call h5aexists_f(dset_id, aname, exists, error)

    if (exists) then
      ! open attribute
      call h5aopen_f(dset_id, aname, attr_id, error)
      ! Get dataspace for attribute
      call h5aget_space_f(attr_id, aspace_id, error)
      ! read attribute data
      call h5aread_f( attr_id, H5T_NATIVE_DOUBLE, attribute, adims, error)
      ! close attribute
      call h5aclose_f(attr_id,error) ! Close the attribute.
      call h5sclose_f(aspace_id,error) ! Terminate access to the data space.
    else
      attribute = 0.d0
    endif

    call h5dclose_f(dset_id,error)
    call h5fclose_f(file_id,error)
    call h5close_f(error) ! Close Fortran interfaces and HDF5 library.
  endif

  call MPI_BCAST( attribute, dim, MPI_DOUBLE_PRECISION, 0, MPI_COMM_WORLD, error )
end subroutine read_attrib_dble


end module hdf5_wrapper
