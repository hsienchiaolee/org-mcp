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

(ert-deftest org-mcp-mutate-capture-cases ()
  "Test all capture input combinations."
  (org-mcp-test-with-temp-org
      "* Projects
:PROPERTIES:
:ID: capture-parent
:END:
"
    (dolist (case `(;; (parent file headline expected)
                    ("capture-parent" nil      "Task A" success)
                    (nil              ,temp-file "Task B" success)
                    ("capture-parent" ,temp-file "Task C" success)
                    (nil              nil      "Task D" error)
                    (nil              ,temp-file nil      error)
                    ("capture-parent" nil      nil      error)
                    (nil              nil      nil      error)))
      (let ((parent (nth 0 case))
            (file (nth 1 case))
            (headline (nth 2 case))
            (expected (nth 3 case)))
        (if (eq expected 'error)
            (should-error
             (org-mcp-mutate-capture :parent parent :file file :headline headline)
             :type 'error)
          (let ((result (org-mcp-mutate-capture
                         :parent parent :file file :headline headline :state "TODO")))
            (should (plist-get result :id))
            (let ((entry (org-mcp-query-get-entry (plist-get result :id))))
              (should (equal (plist-get entry :headline) headline))
              (should (equal (plist-get entry :state) "TODO")))))))))

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

;;; Input validation

(ert-deftest org-mcp-mutate-validate-headline ()
  "Validate headline text rejects empty, whitespace-only, and newlines."
  (org-mcp-test-with-temp-org
      "* TODO Task
:PROPERTIES:
:ID: mut-val-hl
:END:
"
    (dolist (case '(("Valid headline"  success)
                    (""                error)
                    ("   "             error)
                    ("Bad\nheadline"   error)
                    ("* Star heading"  error)
                    ("** Two stars"    error)))
      (if (eq (nth 1 case) 'error)
          (should-error (org-mcp-mutate-set-headline "mut-val-hl" (nth 0 case))
                        :type 'org-mcp-invalid-input)
        (org-mcp-mutate-set-headline "mut-val-hl" (nth 0 case))))))

(ert-deftest org-mcp-mutate-validate-property-key ()
  "Validate property key rejects empty, whitespace-only, and newline keys."
  (org-mcp-test-with-temp-org
      "* TODO Task
:PROPERTIES:
:ID: mut-val-prop
:END:
"
    (dolist (case '(("ASSIGNEE"    success)
                    (""            error)
                    ("   "         error)
                    ("KEY\nINJECT" error)))
      (if (eq (nth 1 case) 'error)
          (should-error (org-mcp-mutate-set-property "mut-val-prop" (nth 0 case) "val")
                        :type 'org-mcp-invalid-input)
        (org-mcp-mutate-set-property "mut-val-prop" (nth 0 case) "val")))))

(ert-deftest org-mcp-mutate-validate-body ()
  "Validate body rejects headings and unbalanced blocks."
  (org-mcp-test-with-temp-org
      "* TODO Task
:PROPERTIES:
:ID: mut-val-body
:END:
"
    (dolist (case '(("Normal text"                     success)
                    ("   "                             success)
                    ("#+BEGIN_SRC\ncode\n#+END_SRC"     success)
                    ("* Injected heading"               error)
                    ("** Also injected"                 error)
                    ("#+BEGIN_SRC\ncode here"           error)))
      (if (eq (nth 1 case) 'error)
          (should-error (org-mcp-mutate-append-body "mut-val-body" (nth 0 case))
                        :type 'org-mcp-invalid-input)
        (org-mcp-mutate-append-body "mut-val-body" (nth 0 case))))))

(provide 'org-mcp-mutate-test)
;;; org-mcp-mutate-test.el ends here
