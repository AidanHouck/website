# Directories to use
TEMP_DIR = .tmp
TEMPLATE_DIR = templates
BLOG_DIR = blogs

# Files to reference
MASTER_TEMPLATE = master.html
MASTER_NEST_TEMPLATE = master_nest.html
ALL_MD = $(filter-out README.md, $(wildcard *.md)) $(wildcard $(BLOG_DIR)/*.md)
ALL_HTML = $(ALL_MD:.md=.html)

# Make the website normally
.PHONY: all
all: preprocess $(ALL_HTML) postprocess

# Preprocess and use 'sed' to replace certain landmarks
# with content from other template HTML files
.PHONY: preprocess
preprocess: $(ALL_TEMPLATES)
	cp $(TEMPLATE_DIR)/$(MASTER_TEMPLATE) $(TEMP_DIR)/$(MASTER_TEMPLATE)
	sed -e '/__header.html__/ {' -e 'r $(TEMPLATE_DIR)/header.html' -e 'd' -e '}' -i $(TEMP_DIR)/$(MASTER_TEMPLATE)
	sed -e '/__footer.html__/ {' -e 'r $(TEMPLATE_DIR)/footer.html' -e 'd' -e '}' -i $(TEMP_DIR)/$(MASTER_TEMPLATE)
	cp $(TEMP_DIR)/$(MASTER_TEMPLATE) $(TEMP_DIR)/$(MASTER_NEST_TEMPLATE)
	sed 's/a href="/a href="..\\/' -i $(TEMP_DIR)/$(MASTER_NEST_TEMPLATE)

# Cleanup temp dir
.PHONY: postprocess
postprocess:
	rm -f $(TEMP_DIR)/*.html

# Use static pattern rule to dynamically build all needed HTML files
# Use if/else to check if the md is in the root dir or a nested dir.
# If a nested dir, run using the secondary template with fixed local file paths.
$(ALL_HTML): %.html: %.md
	@if [ "$(@D)" = "." ]; then \
		pandoc -s --toc -i $< -o $@ --template=$(TEMP_DIR)/$(MASTER_TEMPLATE); \
	else \
		pandoc -s --toc -i $< -o $@ --template=$(TEMP_DIR)/$(MASTER_NEST_TEMPLATE); \
	fi

# Cleanup anything that was generated
.PHONY: clean
clean:
	rm -f *.html $(BLOG_DIR)/*.html $(TEMP_DIR)/*.html

