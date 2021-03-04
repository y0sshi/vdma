default: main

run:  main
	sudo ./main

main: main.cpp
	g++ main.cpp -o main `pkg-config --libs slab_uio`

clean:
	rm -f main
