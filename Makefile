# Directories to use
TEMP_DIR = .tmp
TEMPLATE_DIR = templates
BLOG_DIR = blogs
OUT_DIR = _site
IMG_DIR = images

# Files to reference
MASTER_TEMPLATE = master.html
MASTER_NEST_TEMPLATE = master_nest.html
ALL_MD = $(filter-out README.md, $(wildcard *.md)) $(wildcard $(BLOG_DIR)/*.md)
ALL_HTML = $(ALL_MD:.md=.html)

# Make the website
.PHONY: all
all: preprocess $(ALL_HTML) postprocess

# Preprocess and use 'sed' to replace certain landmarks
# with content from other template HTML files
#
# Also, check for the variable PROD and update local file paths
# based off of that. 
.PHONY: preprocess
preprocess: $(ALL_TEMPLATES)
	mkdir -p "$(TEMP_DIR)" "$(OUT_DIR)" "$(OUT_DIR)/$(BLOG_DIR)"
	ln -ns "${PWD}/$(IMG_DIR)" "./$(OUT_DIR)/$(IMG_DIR)" || true
	cp $(TEMPLATE_DIR)/$(MASTER_TEMPLATE) $(TEMP_DIR)/$(MASTER_TEMPLATE)
	sed -e '/__header.html__/ {' -e 'r $(TEMPLATE_DIR)/header.html' -e 'd' -e '}' -i $(TEMP_DIR)/$(MASTER_TEMPLATE)
	sed -e '/__footer.html__/ {' -e 'r $(TEMPLATE_DIR)/footer.html' -e 'd' -e '}' -i $(TEMP_DIR)/$(MASTER_TEMPLATE)
	cp $(TEMP_DIR)/$(MASTER_TEMPLATE) $(TEMP_DIR)/$(MASTER_NEST_TEMPLATE)
ifndef PROD
	$(info PROD not defined... building with local paths)
	sed 's/a href="/a href="..\\/' -i $(TEMP_DIR)/$(MASTER_NEST_TEMPLATE)
else
	$(info PROD defined... building with remote paths)
	sed 's/a href="/a href="\//' -i $(TEMP_DIR)/$(MASTER_TEMPLATE)
	sed 's/a href="/a href="\//' -i $(TEMP_DIR)/$(MASTER_NEST_TEMPLATE)
endif

# Use static pattern rule to dynamically build all needed HTML files
# Use if/else to check if the md is in the root dir or a nested dir.
# If a nested dir, run using the secondary template with fixed local file paths.
$(ALL_HTML): %.html: %.md
	@if [ "$(@D)" = "." ]; then \
		pandoc -s --toc -i $< -o $(OUT_DIR)/$@ --template=$(TEMP_DIR)/$(MASTER_TEMPLATE); \
	else \
		pandoc -s --toc -i $< -o $(OUT_DIR)/$@ --template=$(TEMP_DIR)/$(MASTER_NEST_TEMPLATE); \
	fi
ifndef PROD
# Remove leading / from navbar if not prod
	sed 's/a href="\//a href="/' -i $(OUT_DIR)/$@
# Add ../ for images if not prod
	sed 's/img src="/img src="..\//' -i $(OUT_DIR)/$@
# Convert forward slash to Windows backslash
#sed '/img src/s/\//\\/g' -i $(OUT_DIR)/$@
else
# Add leading / to filepath if prod
	sed 's/img src="/img src="\//' -i $(OUT_DIR)/$@
endif

# Cleanup temp dir
.PHONY: postprocess
postprocess:
	rm -f $(TEMP_DIR)/*.html

# Cleanup anything that was generated
.PHONY: clean
clean:
	rm -f $(OUT_DIR)/*.html $(OUT_DIR)/$(BLOG_DIR)/*.html $(TEMP_DIR)/*.html
	rm -f $(OUT_DIR)/images

