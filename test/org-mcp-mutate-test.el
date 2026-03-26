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

(ert-deftest org-mcp-mutate-append-body ()
  "Append text to the body of an entry."
  (org-mcp-test-with-temp-org
      "* TODO Task A
:PROPERTIES:
:ID: mut-body-1
:END:
Existing body.
"
    (let ((result (org-mcp-mutate-append-body "mut-body-1" "Appended text." nil)))
      (should (equal (plist-get result :appended) t))
      (let ((entry (org-mcp-query-get-entry "mut-body-1")))
        (should (string-match-p "Existing body" (plist-get entry :body)))
        (should (string-match-p "Appended text" (plist-get entry :body)))))))

(ert-deftest org-mcp-mutate-append-body-drawer ()
  "Append text inside a named drawer."
  (org-mcp-test-with-temp-org
      "* TODO Task A
:PROPERTIES:
:ID: mut-drawer-1
:END:
"
    (org-mcp-mutate-append-body "mut-drawer-1" "Result line." "RESULTS")
    (with-current-buffer (find-file-noselect
                          (car (org-id-find "mut-drawer-1")))
      (org-with-wide-buffer
       (goto-char (cdr (org-id-find "mut-drawer-1")))
       (should (search-forward ":RESULTS:" nil t))
       (should (search-forward "Result line." nil t))
       (should (search-forward ":END:" nil t))))))

(ert-deftest org-mcp-mutate-capture-inline ()
  "Create a new entry from inline params."
  (org-mcp-test-with-temp-org
      "* Projects
:PROPERTIES:
:ID: capture-parent
:END:
"
    (let* ((file (car (org-id-find "capture-parent")))
           (result (org-mcp-mutate-capture
                    :file file
                    :parent "Projects"
                    :headline "New task"
                    :state "TODO"
                    :properties '(("EFFORT" . "1h"))
                    :body "Task body.")))
      (should (plist-get result :id))
      (should (equal (plist-get result :file) file))
      ;; Verify the entry exists
      (let ((entry (org-mcp-query-get-entry (plist-get result :id))))
        (should (equal (plist-get entry :headline) "New task"))
        (should (equal (plist-get entry :state) "TODO"))))))

(ert-deftest org-mcp-mutate-set-headline ()
  "Rename a headline on an entry."
  (org-mcp-test-with-temp-org
      "* TODO Old Name
:PROPERTIES:
:ID: mut-headline-1
:END:
"
    (let ((result (org-mcp-mutate-set-headline "mut-headline-1" "New Name")))
      (should (equal (plist-get result :id) "mut-headline-1"))
      (should (equal (plist-get result :old_headline) "Old Name"))
      (should (equal (plist-get result :new_headline) "New Name"))
      (let ((entry (org-mcp-query-get-entry "mut-headline-1")))
        (should (equal (plist-get entry :headline) "New Name"))
        (should (equal (plist-get entry :state) "TODO"))))))

(provide 'org-mcp-mutate-test)
;;; org-mcp-mutate-test.el ends here
