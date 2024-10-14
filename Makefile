all: index.html

clean:
	rm -f index.html

index.html: index.md template.html Makefile
	pandoc --standalone --template template.html index.md -o index.html

