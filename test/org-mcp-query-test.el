;;; org-mcp-query-test.el --- Tests for query tools -*- lexical-binding: t; -*-

(require 'test-helper)
(require 'org-mcp-query)

(ert-deftest org-mcp-query-get-entry-basic ()
  "Get a full entry by org-id."
  (org-mcp-test-with-temp-org
      "* TODO Implement auth :work:backend:
:PROPERTIES:
:ID: test-abc123
:EFFORT: 2h
:END:
Body text here.
"
    (let ((result (org-mcp-query-get-entry "test-abc123")))
      (should (equal (plist-get result :id) "test-abc123"))
      (should (equal (plist-get result :heading) "Implement auth"))
      (should (equal (plist-get result :state) "TODO"))
      (should (member "work" (plist-get result :tags)))
      (should (member "backend" (plist-get result :tags)))
      (should (equal (plist-get (plist-get result :properties) :EFFORT) "2h"))
      (should (string-match-p "Body text here" (plist-get result :body))))))

(ert-deftest org-mcp-query-get-entry-not-found ()
  "Missing ID signals an error."
  (org-mcp-test-with-temp-org "* TODO Task\n"
    (should-error (org-mcp-query-get-entry "nonexistent")
                  :type 'org-mcp-entry-not-found)))

(ert-deftest org-mcp-query-get-entry-with-ancestors ()
  "Ancestors are returned from parent to root."
  (org-mcp-test-with-temp-org
      "* Project Alpha
:PROPERTIES:
:STACK: Python
:END:
** Sprint 1
*** TODO Implement auth
:PROPERTIES:
:ID: test-nested
:END:
"
    (let* ((result (org-mcp-query-get-entry "test-nested"))
           (ancestors (plist-get result :ancestors)))
      (should (= (length ancestors) 2))
      (should (equal (plist-get (car ancestors) :heading) "Sprint 1"))
      (should (equal (plist-get (cadr ancestors) :heading) "Project Alpha")))))

(ert-deftest org-mcp-query-get-entry-with-timestamps ()
  "Scheduled and deadline timestamps are extracted."
  (org-mcp-test-with-temp-org
      "* TODO Deadline task
SCHEDULED: <2026-03-25 Wed> DEADLINE: <2026-03-28 Sat>
:PROPERTIES:
:ID: test-ts
:END:
"
    (let ((result (org-mcp-query-get-entry "test-ts")))
      (should (equal (plist-get result :scheduled) "2026-03-25"))
      (should (equal (plist-get result :deadline) "2026-03-28"))
      (should (null (plist-get result :closed))))))

(provide 'org-mcp-query-test)
;;; org-mcp-query-test.el ends here
