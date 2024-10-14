TEMP_DIR = .tmp

TEMPLATE_DIR = templates
MASTER_TEMPLATE = master.html
ALL_TEMPLATES = templates/*.html

all: preprocess index.html postprocess

clean:
	rm -f index.html $(TEMP_DIR)/*.html

preprocess: $(ALL_TEMPLATES)
	cp $(TEMPLATE_DIR)/$(MASTER_TEMPLATE) $(TEMP_DIR)/$(MASTER_TEMPLATE)
	sed -e '/__header.html__/ {' -e 'r templates/header.html' -e 'd' -e '}' -i $(TEMP_DIR)/$(MASTER_TEMPLATE)

postprocess:
	rm -f $(TEMP_DIR)/*.html

index.html: index.md $(TEMP_DIR)/$(MASTER_TEMPLATE)
	pandoc -s --toc -i $< -o $@ --template=$(TEMP_DIR)/$(MASTER_TEMPLATE)

