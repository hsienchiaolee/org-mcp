EMACS ?= emacs
BATCH = $(EMACS) --batch -Q -L . -L test

.PHONY: test clean

TEST_FILES := $(wildcard test/org-mcp-*-test.el)
TEST_LOADS := $(patsubst test/%.el,-l %,$(TEST_FILES))

test:
	$(BATCH) -l test-helper $(TEST_LOADS) -f ert-run-tests-batch-and-exit

test-%:
	$(BATCH) -l test-helper -l org-mcp-$*-test -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
