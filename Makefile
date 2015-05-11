TARGET := x64-linux
LDFLAGS := -T src/rs-3/$(TARGET)/link.ld -z max-page-size=0x1000 -s
OUT := target/$(TARGET)

$(OUT)/rs-3/%.o: src/rs-3/$(TARGET)/%.s
	@mkdir -p $(dir $@)
	@echo "Assembling \`$<\`"
	@fasm $< $@

$(OUT)/rs-2/%.o: src/rs-2/%.rs-2 src/rs-2/std.rs-2
	@mkdir -p $(dir $@)
	@echo "Assembling \`$<\`"
	@fasm $< $@

$(OUT)/rs-2/%: $(OUT)/rs-2/%.o $(OUT)/rs-3/vm.o
	@echo "Linking \`$<\`"
	@$(LD) $(LDFLAGS) $^ -o $@

rs-2-example-%: $(OUT)/rs-2/examples/%
	@echo "Running \`$<\`"
	@$<

.PHONY: rs-2-example-%
.SECONDARY:
