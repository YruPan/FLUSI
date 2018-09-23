!====================================================================
!====================================================================
!
!     Fourier transform subroutines using P3DFFT and FFTW3
!
!====================================================================
!====================================================================

module fftw3_descriptors
  use vars
  implicit none
  integer(kind=8),dimension(1:3),save :: Desc_Handle_1D_f,Desc_Handle_1D_b

end module fftw3_descriptors

!---------------------------------------------------------------------
! module that contains wrappers for P3DFFT
!---------------------------------------------------------------------

module p3dfft_wrapper
  use vars
  implicit none

  contains

! Compute the FFT of the real-valued 3D array inx and save the output
! in the complex-valued 3D array outk.
subroutine fft(outk,inx)
    use mpi
    use vars ! For precision specficiation and array sizes
    real(kind=pr),intent(in)::inx(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
    complex(kind=pr),intent(out)::outk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))

    call coftxyz(inx,outk)
end subroutine fft


! Compute the inverse FFT of the complex-valued 3D array ink and save the
! output in the real-valued 3D array outx.
subroutine ifft(outx,ink)
    use mpi
    use vars ! For precision specficiation and array sizes
    complex(kind=pr),intent(in)::ink(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
    real(kind=pr),intent(out)::outx(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))

    call cofitxyz(ink,outx)
end subroutine ifft


! Compute the FFT of the real-valued 3D array inx and save the output
! in the complex-valued 3D array outk.
subroutine fft3(outk,inx)
    use mpi
    use vars ! For precision specficiation and array sizes
    real(kind=pr),intent(in)::inx(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
    complex(kind=pr),intent(out)::outk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3)
    call coftxyz(inx(:,:,:,1),outk(:,:,:,1))
    call coftxyz(inx(:,:,:,2),outk(:,:,:,2))
    call coftxyz(inx(:,:,:,3),outk(:,:,:,3))
end subroutine fft3


! Compute the inverse FFT of the complex-valued 3D array ink and save the
! output in the real-valued 3D array outx.
subroutine ifft3(outx,ink)
    use mpi
    use vars ! For precision specficiation and array sizes
    complex(kind=pr),intent(in)::ink(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:3)
    real(kind=pr),intent(out)::outx(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:3)
    call cofitxyz(ink(:,:,:,1),outx(:,:,:,1))
    call cofitxyz(ink(:,:,:,2),outx(:,:,:,2))
    call cofitxyz(ink(:,:,:,3),outx(:,:,:,3))
end subroutine ifft3

subroutine fft_initialize
  !-----------------------------------------------------------------------------
  !     Allocate memory and initialize FFT
  !-----------------------------------------------------------------------------
  ! This subroutine performs two major tasks:
  !     * Initialize P3DFFT and provide the memory management (how big are the
  !       chunks of data on each process (coftxyz and cofitxyz)
  !     * Initialize 1D transforms that rely on FFTW (cofts and cofits)
  !       the auxiliary subroutine textents is used here
  !-----------------------------------------------------------------------------
  use mpi ! Module incapsulates mpif.
  use vars
  use p3dfft
  use fftw3_descriptors
  implicit none
  include 'fftw3.f'

  integer,parameter :: nmpidims = 2
  integer :: mpicode,idir,L,n,ix,iy,iz
  integer,dimension(1:3) :: ka,kb,ks,kat,kbt,kst
  logical,dimension(2) :: subcart
  real(kind=pr),dimension(:,:),allocatable :: f,ft
  integer, dimension(:,:), allocatable :: yz_plane_local
  real(kind=pr) :: k

  !-----------------------------------------------------------------------------
  !------ Three-dimensional FFT                                           ------
  !-----------------------------------------------------------------------------
  ! default case, no decomposition
  decomposition="none"

  if (mpirank==0) then
    write(*,'(A)') "-----------------------------------p3dfft init---------------------------"
    write(*,'("Initializing P3DFFT, n=(",3(i4,1x),")")') nx,ny,nz
    write(*,'("P3DFFT reserves about ",i8,"MB (",i4,"GB) for internal work arrays")') &
    nint(1.6d-5*dble(nx)*dble(ny)*dble(nz)), nint(1.6d-5*dble(nx)*dble(ny)*dble(nz)/1000.d0)
  endif

  !-- Set up dimensions. It is very important that mpidims(2) > mpidims(1)
  ! because P3Dfft crashes otherwise. This means a 1D decomposition is always
  ! along the z direction in real space.
  if (nz>mpisize) then
     mpidims(1) = 1             ! due to p3dfft, 1D decomposition is always the
     mpidims(2) = mpisize       ! 3rd index in real space.
     decomposition="1D"
  else
     mpidims(1) = 0
     mpidims(2) = 0
     call MPI_Dims_create(mpisize,nmpidims,mpidims,mpicode)
     if(mpidims(1) > mpidims(2)) then
        mpidims(1) = mpidims(2)
        mpidims(2) = mpisize / mpidims(1)
     endif
     decomposition="2D"
  endif

  if (root) write(*,'("mpidims= ",i3,1x,i3)') mpidims
  if (root) write(*,'("Using ",A," decomposition!")') trim(adjustl(decomposition))

  !-- Check dimensions
  if(mpidims(1)*mpidims(2)/=mpisize) then
    call abort(90001,"wrong mpidims: change mpisize")
  endif

  !-- Initialize P3DFFT
  call p3dfft_setup(mpidims,nx,ny,nz,MPI_COMM_WORLD, overwrite=.false.)

  !-- Get Cartesian topology info
  call p3dfft_get_mpi_info(mpitaskid,mpitasks,mpicommcart)

  !-- Get local sizes
  call p3dfft_get_dims(ra,rb,rs,1)  ! real blocks
  call p3dfft_get_dims(ca,cb,cs,2)  ! complex blocks
  ra(:) = ra(:) - 1
  rb(:) = rb(:) - 1
  ca(:) = ca(:) - 1
  cb(:) = cb(:) - 1

  !-- extends of real arrays that have ghost points. We add ghosts in all
  !-- directions, including the periodic ones.
  ga=ra-ng
  gb=rb+ng

  if (nx==1) then
    ga(1)=0
    gb(1)=0
  endif

  if ( rb(2)-ra(2)+1<2*ng .or. rb(3)-ra(3)+1<2*ng ) then
    if (mpirank==0) write(*,*) "Too many CPUs: the ghosts span more than one CPU"
    if (mpirank==0) write(*,*) "y", rb(2)-ra(2)+1, "z", rb(3)-ra(3)+1
    call abort(9002)
  endif

  !-- Allocate domain partitioning tables and gather sizes from all processes
  !-- (only for real arrays)
  allocate ( ra_table(1:3,0:mpisize-1), rb_table(1:3,0:mpisize-1) )
  call MPI_ALLGATHER (ra, 3, MPI_INTEGER, ra_table, 3, MPI_INTEGER, MPI_COMM_WORLD, mpicode)
  call MPI_ALLGATHER (rb, 3, MPI_INTEGER, rb_table, 3, MPI_INTEGER, MPI_COMM_WORLD, mpicode)

  !-- create a 2D array of size ny*nz that holds the mpirank of every point
  !-- in the y-z plane
  allocate (yz_plane_ranks(0:ny-1,0:nz-1) )
  allocate (yz_plane_local(0:ny-1,0:nz-1) )

  yz_plane_local = 0
  yz_plane_local( ra(2):rb(2), ra(3):rb(3) ) = mpirank

  call MPI_ALLREDUCE ( yz_plane_local,yz_plane_ranks,ny*nz,&
                      MPI_INTEGER,MPI_SUM,MPI_COMM_WORLD,mpicode)

  !-- save the 2D decomposition to disk
  if (mpirank==0) then
    open(14,file='decomposition',status='replace')
    do n=0,ny-1
      do L=0,nz-1
        write(14,'(i4.4,1x)',advance='no') yz_plane_ranks(n,L)
      enddo
      write(14,'(A)',advance='yes') " "
    enddo
    close(14)
  endif


!   !-----------------------------------------------------------------------------
!   ! ------ Multiple one-dimensional FFTs                                  ------
!   !-----------------------------------------------------------------------------
!   !-- Create Cartesian topology for one-dimensional transforms
!   call MPI_CART_CREATE(MPI_COMM_WORLD,nmpidims,mpidims,(/.false.,.false./),&
!        .false.,mpicommcart,mpicode)
!   ! call MPI_CART_CREATE(MPI_COMM_WORLD,nmpidims,mpidims,(/0,0/),0,mpicommcart,mpicode)
!   call MPI_CART_COORDS(mpicommcart,mpirank,nmpidims,mpicoords,mpicode)
!
!   !-- Restrict communications to slabs:
!   !-- Communicate between processes which have the same second(for idir=1) or third(for idir=2) index in the cartesian topology
!   do idir = 1,2
!      subcart(3-idir) = .true.
!      subcart(idir) = .false.
!      call MPI_CART_SUB(mpicommcart,subcart,mpicommslab(idir),mpicode)
!   enddo
!
!   !-- Create FFTW plans for all possible sizes
!   ! extents of arrays before and after transpose x->y
!   call trextents(1,(/nx,ny,nz/),mpidims,mpicoords,ka,kb,ks,kat,kbt,kst)
!
!   ! allocate plan for transform with x leading
!   L = nx
!   n = ks(2)*ks(3)
!   allocate(f(0:L-1,0:n-1),ft(0:L+1,0:n-1) )
!   call dfftw_plan_many_dft_r2c(Desc_Handle_1D_f(1),1,L,n,f,0,1,L,ft,0,1,L/2+1,&
!        FFTW_ESTIMATE)
!   call dfftw_plan_many_dft_c2r(Desc_Handle_1D_b(1),1,L,n,ft,0,1,L/2+1,f,0,1,L,&
!        FFTW_ESTIMATE)
!   deallocate(f,ft )
!
!   ! allocate plan for transform with y leading
!   L = ny
!   n = kst(2)*kst(3)
!   allocate(f(0:L-1,0:n-1),ft(0:L+1,0:n-1) )
!   call dfftw_plan_many_dft_r2c(Desc_Handle_1D_f(2),1,L,n,f,0,1,L,ft,0,1,L/2+1,&
!        FFTW_ESTIMATE)
!   call dfftw_plan_many_dft_c2r(Desc_Handle_1D_b(2),1,L,n,ft,0,1,L/2+1,f,0,1,L,&
!        FFTW_ESTIMATE)
!   deallocate(f,ft )
!
!   ! extents of arrays before and after transpose y->z
!   call trextents(2,(/ny,nx,nz/),mpidims,mpicoords,ka,kb,ks,kat,kbt,kst)
!
!   ! allocate plan for transform with z leading
!   L = nz
!   n = kst(2)*kst(3)
!   allocate(f(0:L-1,0:n-1),ft(0:L+1,0:n-1) )
!   call dfftw_plan_many_dft_r2c(Desc_Handle_1D_f(3),1,L,n,f,0,1,L,ft,0,1,L/2+1,&
!        FFTW_ESTIMATE)
!   call dfftw_plan_many_dft_c2r(Desc_Handle_1D_b(3),1,L,n,ft,0,1,L/2+1,f,0,1,L,&
!        FFTW_ESTIMATE)
!   deallocate(f,ft )
!   deallocate (yz_plane_local)
if (mpirank==0) write(*,'(A)') "------------------------------p3dfft init DONE---------------------------"
end subroutine fft_initialize


!-------------------------------------------------------------------------------

subroutine setup_cart_groups
  ! Setup 1d communicators
  use mpi
  use vars
  use p3dfft

  implicit none
  integer :: mpicolor,mpikey,mpicode
  integer :: mpicommtmp1,mpicommtmp2
  logical :: mpiperiods(2),periods(1),reorder
!  integer :: mpiperiods(2),periods(1),reorder
  integer :: one=1,two=2,dims(1) ! Required for MPI_CART_GET, MPI_CART_CREATE in openmpi

  if (mpirank==0) write(*,*) " setting up cart_groups..."

  ! Set parameters
  periods(1)=.true. ! This should be an array - if not, openmpi fails
  reorder=.false.
!  periods(1)=1
!  reorder=0

  ! Get Cartesian topology information
  call MPI_CART_GET(mpicommcart,two,mpidims,mpiperiods,mpicoords,mpicode)
  ! Communicator for line in y direction
  mpicolor = mpicoords(2)
  mpikey = mpicoords(1)
  call MPI_COMM_SPLIT (mpicommcart,mpicolor,mpikey,mpicommtmp1,mpicode)
  dims(1) = mpidims(1)
  call MPI_CART_CREATE(mpicommtmp1,one,dims,periods,reorder,mpicommz,mpicode)
  ! Communicator for line in z direction
  mpicolor = mpicoords(1)
  mpikey = mpicoords(2)
  call MPI_COMM_SPLIT (mpicommcart,mpicolor,mpikey,mpicommtmp2,mpicode)
  dims(1) = mpidims(2)
  call MPI_CART_CREATE(mpicommtmp2,one,dims,periods,reorder,mpicommy,mpicode)

  if (mpirank==0) write(*,*) " done setting up cart_groups!"
end subroutine setup_cart_groups



subroutine fft_free
  !====================================================================
  !     Free memory allocated for FFT
  !====================================================================
  use vars
  use p3dfft
  use fftw3_descriptors
  implicit none

  integer :: j

  !-- Clean 3d workspace
  if(mpirank ==0) then
     write(*,*) "*** cleaning FFT"
  endif

  call p3dfft_clean

  !-- Clean 1d workspaces
  do j = 1,3
     call dfftw_destroy_plan(Desc_Handle_1D_f(j))
     call dfftw_destroy_plan(Desc_Handle_1D_b(j))
  enddo

  if (allocated(yz_plane_ranks)) deallocate(yz_plane_ranks)
  if (allocated(ra_table)) deallocate(ra_table)
  if (allocated(rb_table)) deallocate(rb_table)

end subroutine fft_free


subroutine coftxyz(f,fk)
  !====================================================================
  !     Calculation of the Fourier-coefficients of a real function
  !     along x(1st index),y(2nd index),and z(3rd index)
  !====================================================================
  use vars
  use p3dfft
  use mpi
  implicit none

  real(kind=pr),intent(in) ::  f(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  complex(kind=pr),intent(out) ::  fk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  real(kind=pr),save :: t1
  real(kind=pr) :: norm
  integer(kind=8) :: npoints

  t1 = MPI_wtime()
  ! Compute forward FFT
  call p3dfft_ftran_r2c(f,fk,'fff')

  ! Normalize
!  npoints = int(nx,kind=int64) * int(ny,kind=int64) * int(nz,kind=int64)
  npoints = int(nx,kind=8) * int(ny,kind=8) * int(nz,kind=8)
  norm = 1.d0 / dble(npoints)
  fk(:,:,:) = fk(:,:,:) * norm

  time_fft  = time_fft  + MPI_wtime() - t1  ! for global % of FFTS
end subroutine coftxyz

!-------------------------------------------------------------------------------

subroutine cofitxyz(fk,f)
  !====================================================================
  !     Calculation of a real function from its Fourier coefficients
  !     along x(1st index),y(2nd index),and z(3rd index)
  !====================================================================
  use vars
  use p3dfft
  use mpi
  implicit none

  complex(kind=pr),intent(in) ::  fk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  real(kind=pr),intent(out) ::  f(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),save :: t1
  t1 = MPI_wtime()

  ! Compute backward FFT
  call p3dfft_btran_c2r(fk,f,'fff')


  time_ifft  = time_ifft  + MPI_wtime() - t1
end subroutine cofitxyz

!-------------------------------------------------------------------------------

subroutine cofts(iplan,f,fk,L,n)
  !====================================================================
  !     Calculation of the Fourier coefficients of n real functions
  !     aligned in columns
  !     FILTERING
  !     FFTW3 library is used
  !====================================================================
  use vars
  use fftw3_descriptors
  implicit none
  include 'fftw3.f'

  integer,intent(in) :: iplan,L,n
  integer :: j
  real(kind=pr),dimension(:,:),allocatable :: ft
  real(kind=pr),dimension(0:L-1,0:n-1),intent(in) ::  f
  real(kind=pr),dimension(0:L-1,0:n-1),intent(out) ::  fk
  real(kind=pr) :: norm

  allocate(ft(0:L+1,0:n-1) )

  call dfftw_execute_dft_r2c(Desc_Handle_1D_f(iplan),f,ft)

  ! Output
  norm = 1.0d0 / real(L)
  do j=0,n-1
     fk(:,j) = ft(0:L-1,j) * norm
  end do

  deallocate(ft )

  !      last mode M=L, L+1; mode KF left unconsidered => filtering
end subroutine cofts

!-------------------------------------------------------------------------------

subroutine cofits(iplan,fk,f,L,n)
  !====================================================================
  !     Calculation of n real functions from their Fourier coefficients
  !     aligned in columns
  !     FILTERING
  !     FFTW3 library is used
  !====================================================================
  use vars
  use fftw3_descriptors
  implicit none
  include 'fftw3.f'

  integer,intent(in) :: iplan,L,n
  integer :: j
  real(kind=pr),dimension(:,:),allocatable :: ft
  real(kind=pr),dimension(0:L-1,0:n-1),intent(in) ::  fk
  real(kind=pr),dimension(0:L-1,0:n-1),intent(out) ::  f

  allocate(ft(0:L+1,0:n-1) )

  ! Input
  do j=0,n-1
     ft(0:L-1,j) = fk(:,j)
     ft(L:L+1,j) = 0.0d0
  end do

  call dfftw_execute_dft_c2r(Desc_Handle_1D_b(iplan),ft,f)

  deallocate(ft )

  ! last mode M=L, L+1; mode KF left unconsidered => filtering
end subroutine cofits

! Compute extents of transposed arrays
subroutine trextents(idir,n,mpidims,mpicoords,ka,kb,ks,kat,kbt,kst )
  implicit none

  integer,intent(in) :: idir
  integer,dimension(1:3),intent(in) :: n
  integer,dimension(2),intent(in) :: mpidims,mpicoords
  integer,dimension(1:3),intent(out) :: ka,kb,ks,kat,kbt,kst

  ka(1) = 0
  kb(1) = n(1)-1
  ka(2) = mpicoords(2)*n(2)/mpidims(2)
  kb(2) =(mpicoords(2)+1)*n(2)/mpidims(2)-1
  ka(3) = mpicoords(1)*n(3)/mpidims(1)
  kb(3) =(mpicoords(1)+1)*n(3)/mpidims(1)-1
  ks(:) = kb(:)-ka(:)+1

  kat(1) = 0
  kbt(1) = n(idir+1)-1
  kat(1+idir) = mpicoords(3-idir)*n(1)/mpidims(3-idir)
  kbt(1+idir) =(mpicoords(3-idir)+1)*n(1)/mpidims(3-idir)-1
  kat(4-idir) = ka(4-idir)
  kbt(4-idir) = kb(4-idir)
  kst(:) = kbt(:)-kat(:)+1

end subroutine trextents


!----------------------------------------------------------------
! wavenumber functions: return the kx,ky,kz wavenumbers
! as a function of the array index
!----------------------------------------------------------------

real(kind=pr) function wave_x( ix )
  use vars ! for scale and precision statement
  implicit none
  integer, intent (in) :: ix
  wave_x = scalex*dble(ix)
end function

real(kind=pr) function wave_y( iy )
  use vars ! for scale and precision statement
  implicit none
  integer, intent (in) :: iy
  wave_y = scaley*dble(modulo(iy+ny/2,ny)-ny/2)
end function

real(kind=pr) function wave_z( iz )
  use vars ! for scale and precision statement
  implicit none
  integer, intent (in) :: iz
  wave_z = scalez*dble(modulo(iz+nz/2,nz)-nz/2)
end function

end module p3dfft_wrapper
