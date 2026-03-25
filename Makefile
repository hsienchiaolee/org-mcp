EMACS ?= emacs
BATCH = $(EMACS) --batch -Q -L . -L test

.PHONY: test clean

test:
	$(BATCH) -l test-helper -l org-mcp-rpc-test -l org-mcp-query-test \
	  -l org-mcp-mutate-test -l org-mcp-notify-test -l org-mcp-server-test \
	  -f ert-run-tests-batch-and-exit

test-%:
	$(BATCH) -l test-helper -l org-mcp-$*-test -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
