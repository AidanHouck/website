template = templates/master.html

all: index.html

clean:
	rm -f index.html

index.html: index.md $(template)
	pandoc -s --toc --css css/style.css -i $< -o $@ --template=$(template)

