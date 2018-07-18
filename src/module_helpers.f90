module module_helpers
    use vars, only: strlen, pr, pi
    use mpi
    implicit none

    ! module global variables


contains

    !-----------------------------------------------------------------------------
    ! This function returns, to a given filename, the corresponding dataset name
    ! in the hdf5 file, following flusi conventions (folder/ux_0000.h5 -> "ux")
    !-----------------------------------------------------------------------------
    character(len=strlen)  function get_dsetname(fname)
        implicit none
        character(len=*), intent(in) :: fname
        ! extract dsetname (from "/" until "_", excluding both)
        get_dsetname  = fname  ( index(fname,'/',.true.)+1:index( fname, '_',.true. )-1 )
        return
    end function get_dsetname



    !-------------------------------------------------------------------------------
    ! evaluate a fourier series given by the coefficents a0,ai,bi
    ! at the time "time", return the function value "u" and its
    ! time derivative "u_dt". Uses assumed-shaped arrays, requires an interface.
    !-------------------------------------------------------------------------------
    subroutine fseries_eval(time,u,u_dt,a0,ai,bi)
        implicit none

        real(kind=pr), intent(in) :: a0, time
        real(kind=pr), intent(in), dimension(:) :: ai,bi
        real(kind=pr), intent(out) :: u, u_dt
        real(kind=pr) :: c,s,f
        integer :: nfft, i

        nfft=size(ai)

        ! frequency factor
        f = 2.d0*pi

        u = 0.5d0*a0
        u_dt = 0.d0

        do i=1,nfft
            s = dsin(f*dble(i)*time)
            c = dcos(f*dble(i)*time)
            ! function value
            u    = u + ai(i)*c + bi(i)*s
            ! derivative (in time)
            u_dt = u_dt + f*dble(i)*(-ai(i)*s + bi(i)*c)
        enddo
    end subroutine fseries_eval


    !-------------------------------------------------------------------------------
    ! evaluate hermite series, given by coefficients ai (function values)
    ! and bi (derivative values) at the locations x. Note that x is assumed periodic;
    ! do not include x=1.0.
    ! a valid example is x=(0:N-1)/N
    !-------------------------------------------------------------------------------
    subroutine hermite_eval(time,u,u_dt,ai,bi)
        implicit none

        real(kind=pr), intent(in) :: time
        real(kind=pr), intent(in), dimension(:) :: ai,bi
        real(kind=pr), intent(out) :: u, u_dt
        real(kind=pr) :: dt,h00,h10,h01,h11,t
        integer :: n, j1,j2

        n=size(ai)

        dt = 1.d0 / dble(n)
        j1 = floor(time/dt) + 1
        j2 = j1 + 1
        ! periodization
        if (j2 > n) j2=1
        ! normalized time (between two data points)
        t = (time-dble(j1-1)*dt) /dt

        ! values of hermite interpolant
        h00 = (1.d0+2.d0*t)*((1.d0-t)**2)
        h10 = t*((1.d0-t)**2)
        h01 = (t**2)*(3.d0-2.d0*t)
        h11 = (t**2)*(t-1.d0)

        ! function value
        u = h00*ai(j1) + h10*dt*bi(j1) &
        + h01*ai(j2) + h11*dt*bi(j2)

        ! derivative values of basis functions
        h00 = 6.d0*t**2 - 6.d0*t
        h10 = 3.d0*t**2 - 4.d0*t + 1.d0
        h01 =-6.d0*t**2 + 6.d0*t
        h11 = 3.d0*t**2 - 2.d0*t

        ! function derivative value
        u_dt = (h00*ai(j1) + h10*dt*bi(j1) &
        + h01*ai(j2) + h11*dt*bi(j2) ) / dt
    end subroutine hermite_eval


    function mpisum( a )
        implicit none
        real(kind=pr) :: a_loc, mpisum
        real(kind=pr),intent(in) :: a
        integer :: mpicode
        a_loc=a
        call MPI_ALLREDUCE (a_loc,mpisum,1, MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)
    end function

    function mpimax( a )
        implicit none
        real(kind=pr) :: a_loc, mpimax
        real(kind=pr),intent(in) :: a
        integer :: mpicode
        a_loc=a
        call MPI_ALLREDUCE (a_loc,mpimax,1, MPI_DOUBLE_PRECISION,MPI_MAX,MPI_COMM_WORLD,mpicode)
    end function

    function mpimin( a )
        implicit none
        real(kind=pr) :: a_loc, mpimin
        real(kind=pr),intent(in) :: a
        integer :: mpicode
        a_loc=a
        call MPI_ALLREDUCE (a_loc,mpimin,1, MPI_DOUBLE_PRECISION,MPI_MIN,MPI_COMM_WORLD,mpicode)
    end function

    real (kind=pr) function interp2_nonper (x_target, y_target, field2, axis)
        !  LINEAR Interpolation in a field. The field is of automatic size, indices starting with 0 both. The domain is
        !  defined by x1_box,y1_box and x2_box,y2_box. The target coordinates should lie within that box.
        !  NOTE: attention on the upper point of the box. In the rest of the code, which is periodic, the grid is 0:nx-1
        !        but the lattice spacing is yl/nx. This means that the point (nx-1) has NOT the coordinate yl but yl-dx
        !        (otherwise this point would exist two times!)
        implicit none
        integer :: i,j
        real (kind=pr) :: x,y,x_1,y_1,x_2,y_2,dx, dy, R1,R2
        real (kind=pr), intent (in) :: field2(0:,0:), x_target, y_target, axis(1:4)
        real(kind=pr) :: x1_box, y1_box, x2_box, y2_box

        x1_box = axis(1)
        x2_box = axis(2)
        y1_box = axis(3)
        y2_box = axis(4)


        dx = (x2_box-x1_box) / dble(size(field2,1)-1 )
        dy = (y2_box-y1_box) / dble(size(field2,2)-1 )


        if ( (x_target > x2_box).or.(x_target < x1_box).or.(y_target > y2_box).or.(y_target < y1_box) ) then
            ! return zero if point lies outside valid bounds
            interp2_nonper = 0.0d0
            return
        endif

        i = int((x_target-x1_box)/dx)
        j = int((y_target-y1_box)/dy)

        x_1 = dble(i)*dx + x1_box
        y_1 = dble(j)*dy + y1_box
        x_2 = dx*dble(i+1) + x1_box
        y_2 = dy*dble(j+1) + y1_box
        R1 = (x_2-x_target)*field2(i,j)/dx   + (x_target-x_1)*field2(i+1,j)/dx
        R2 = (x_2-x_target)*field2(i,j+1)/dx + (x_target-x_1)*field2(i+1,j+1)/dx

        interp2_nonper = (y_2-y_target)*R1/dy + (y_target-y_1)*R2/dy

    end function interp2_nonper


    ! checks if a given file ("fname") exists. if not, code is stopped brutally
    subroutine check_file_exists(fname)
      use vars
      use mpi
      implicit none

      character (len=*), intent(in) :: fname
      logical :: exist1
      integer :: mpicode

      inquire ( file=fname, exist=exist1 )
      if ( exist1 .eqv. .false.) then
        call abort(223,"file "//trim(adjustl(fname))// " not found")
      endif

    end subroutine check_file_exists



    ! overwrite and initialize file
    subroutine init_empty_file( fname )
      use vars
      implicit none
      character (len=*), intent(in) :: fname

      if (root) then
        open (15, file=fname, status='replace')
        close(15)
      endif

    end subroutine

end module module_helpers
