# website

A website written in Markdown, converted to HTML using Pandoc/Make.

## Building
```
# Build with local paths/navigation
make

# Build for web server paths/navigation
make PROD=1

# Cleanup generated files
make clean
```

### Building with WSL
If using WSL for development you cannot follow the symlink that is automatically created for images without hosting a local server. This can be done quickly with Python:
```
cd _site/
python3 -m http.server
```

Then connect in a browser to `localhost:8000`

