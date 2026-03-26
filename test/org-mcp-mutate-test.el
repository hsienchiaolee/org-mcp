;;; org-mcp-mutate-test.el --- Tests for mutation tools -*- lexical-binding: t; -*-

(require 'test-helper)
(require 'org-mcp-mutate)

(ert-deftest org-mcp-mutate-set-state ()
  "Set TODO state on an entry."
  (org-mcp-test-with-temp-org
      "* TODO Task A
:PROPERTIES:
:ID: mut-state-1
:END:
"
    (let ((result (org-mcp-mutate-set-state "mut-state-1" "DONE")))
      (should (equal (plist-get result :id) "mut-state-1"))
      (should (equal (plist-get result :old_state) "TODO"))
      (should (equal (plist-get result :new_state) "DONE"))
      ;; Verify the buffer was actually changed
      (let ((entry (org-mcp-query-get-entry "mut-state-1")))
        (should (equal (plist-get entry :state) "DONE"))))))

(ert-deftest org-mcp-mutate-set-state-clear ()
  "Clear TODO state by passing nil."
  (org-mcp-test-with-temp-org
      "* TODO Task B
:PROPERTIES:
:ID: mut-state-2
:END:
"
    (let ((result (org-mcp-mutate-set-state "mut-state-2" nil)))
      (should (equal (plist-get result :old_state) "TODO"))
      (should (null (plist-get result :new_state)))
      (let ((entry (org-mcp-query-get-entry "mut-state-2")))
        (should (null (plist-get entry :state)))))))

(ert-deftest org-mcp-mutate-set-property ()
  "Set a property on an entry."
  (org-mcp-test-with-temp-org
      "* TODO Task C
:PROPERTIES:
:ID: mut-prop-1
:END:
"
    (let ((result (org-mcp-mutate-set-property "mut-prop-1" "ASSIGNEE" "alice")))
      (should (equal (plist-get result :id) "mut-prop-1"))
      (should (equal (plist-get result :key) "ASSIGNEE"))
      (should (equal (plist-get result :value) "alice"))
      ;; Verify the property was actually set
      (let ((props (plist-get (org-mcp-query-get-properties "mut-prop-1") :properties)))
        (should (equal (plist-get props :ASSIGNEE) "alice"))))))

(ert-deftest org-mcp-mutate-set-property-delete ()
  "Delete a property by passing nil value."
  (org-mcp-test-with-temp-org
      "* TODO Task D
:PROPERTIES:
:ID: mut-prop-2
:ASSIGNEE: bob
:END:
"
    (let ((result (org-mcp-mutate-set-property "mut-prop-2" "ASSIGNEE" nil)))
      (should (equal (plist-get result :id) "mut-prop-2"))
      (should (equal (plist-get result :key) "ASSIGNEE"))
      (should (null (plist-get result :value)))
      ;; Verify the property was deleted
      (let ((props (plist-get (org-mcp-query-get-properties "mut-prop-2") :properties)))
        (should (null (plist-get props :ASSIGNEE)))))))

(provide 'org-mcp-mutate-test)
;;; org-mcp-mutate-test.el ends here
