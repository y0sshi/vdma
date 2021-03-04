//-----------------------------------------------------------------------------
// <uio.hpp>
//  - Header of slab::UIO class
//    - Declared of slab::UIO class
//    - Declared of slab::mutex class
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 23, 2020)
//  - Added declaration of slab::UIO class
//  - Added declaration of slab::mutex class
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------

#ifndef _UIO_H_
#define _UIO_H_

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>
#include <stdint.h>

#include <string>

#define WRITE_ADDR   0x0
#define WRITE_VALUE  0x1
#define WRITE_ENABLE 0x2
#define READ_ADDR    0x3

namespace slab {
	class mutex {
		private:
			/* 
			 * true  : locked, 
			 * false : unlocked 
			*/
			bool mtx;
		protected:
		public:
			mutex();
			~mutex();
			void lock();
			void unlock();
	};

	class UIO {
		private:
			uint32_t *reg_;
			int uiofd_;
			bool open_flag_;
			mutex mtx_w_;
			mutex mtx_r_;
		protected:
		public:
			UIO();
			UIO(const char*);
			UIO(std::string);
			~UIO();
			bool open_device(const char*);
			bool close_device();
			int read(int addr);
			void write(int addr, int data);
	};
};

#endif
