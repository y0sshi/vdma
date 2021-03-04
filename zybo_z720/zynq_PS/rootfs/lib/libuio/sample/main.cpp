#include <stdio.h>
#include <iostream>
#include <string>
#include <slab/uio.hpp>

void str2int(std::string str, int &v);

int main() {
	int addr, value;
	std::string str;
	bool exit_flag = false;
	slab::UIO fpga("/dev/uio0");

	std::cout << "########################" << std::endl;
	std::cout << "# read  <addr>         #" << std::endl;
	std::cout << "# write <addr> <value> #" << std::endl;
	std::cout << "# exit                 #" << std::endl;
	std::cout << "########################" << std::endl << std::endl;
	while (exit_flag == false) {
		std::cout << ">> ";
		std::cin >> str; // operation
		if (!str.compare(std::string("exit"))) {
			exit_flag = true;
		}
		else if (!str.compare(std::string("read"))) {
			std::cin >> str; // address
			str2int(str, addr);
			printf("0x%X\n", fpga.read(addr));
		}
		else if (!str.compare(std::string("write"))) {
			std::cin >> str; // address
			str2int(str, addr);
			std::cin >> str; // value
			str2int(str, value);
			fpga.write(addr, value);
		}
	}
	return 0;
}

void str2int(std::string str, int &v) {
	if (str.compare(0, 2, std::string("0x"))) { // decimal
		sscanf(str.c_str(), "%d", &v);
	}
	else { // hexdecimal
		sscanf(str.c_str(), "%x", &v);
	}
}
