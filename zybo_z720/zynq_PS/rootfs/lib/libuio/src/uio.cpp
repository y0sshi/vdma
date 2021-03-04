//-----------------------------------------------------------------------------
// <uio.cpp>
//  - Defined functions of slab::UIO class and slab::mutex class
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 23, 2020)
//  - Added definition for functions of slab::UIO class
//  - Added definition for functions of slab::mutex class
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------


#include <slab/uio.hpp>

namespace slab {
	mutex::mutex() {
		mtx = false;
	}

	mutex::~mutex() {
		mtx = false;
	}

	void mutex::lock() {
		while (mtx);
		mtx = true;
	}

	void mutex::unlock() {
		mtx = false;
	}

	UIO::UIO() {
		open_flag_ = false;
	}

	UIO::UIO(const char *dev) {
		open_flag_ = false;
		if (!open_flag_) {
			printf("openning %s...\n", dev);
			open_device(dev);
			printf("done !!\n");
		}
	}

	UIO::UIO(std::string dev) {
		open_flag_ = false;
		if (!open_flag_) {
			printf("openning %s...\n", dev.c_str());
			open_device(dev.c_str());
			printf("done !!\n");
		}
	}

	UIO::~UIO() {
		if (open_flag_) {
			printf("free device...\n");
			close_device();
			printf("done !!\n");
		}
	}

	bool UIO::open_device(const char* dev) {
		if (!open_flag_) {
			/* open device */
			if ((uiofd_ = open(dev, O_RDWR | O_SYNC)) < 0) {
				perror("cannot open device\n");
				return false;
			}

			/* mmap register */
			reg_ = (uint32_t *)mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, uiofd_, 0);
			if (reg_ == MAP_FAILED) {
				perror("cannot mmap reg_");
				close(uiofd_);
				return false;
			}

			/* change flag */
			open_flag_ = true;
		}
		return true;
	}

	bool UIO::close_device() {
		if (open_flag_) {
			munmap((void*)reg_, 0x1000);
			close(uiofd_);
			open_flag_ = false;
		}
		return true;
	}

	int UIO::read(int addr) {
		int data;

		mtx_r_.lock();
		data = reg_[addr];
		mtx_r_.unlock();

		return data;
	}

	void UIO::write(int addr, int data) {
		mtx_w_.lock();
		reg_[addr] = data;
		mtx_w_.unlock();
	}
};
