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

(ert-deftest org-mcp-mutate-capture-with-properties ()
  "Capture with properties sets them on the new entry."
  (org-mcp-test-with-temp-org
      "* Projects
:PROPERTIES:
:ID: cap-props-parent
:END:
"
    (let ((result (org-mcp-mutate-capture
                   :parent "cap-props-parent"
                   :headline "New Task"
                   :state "TODO"
                   :properties '(:EFFORT "2h" :ASSIGNEE "alice"))))
      (should (plist-get result :id))
      (let ((props (plist-get (org-mcp-query-get-properties (plist-get result :id)) :properties)))
        (should (equal (plist-get props :EFFORT) "2h"))
        (should (equal (plist-get props :ASSIGNEE) "alice"))))))

(ert-deftest org-mcp-mutate-capture-with-body ()
  "Capture with body text inserts it in the new entry."
  (org-mcp-test-with-temp-org
      "* Projects
:PROPERTIES:
:ID: cap-body-parent
:END:
"
    (let ((result (org-mcp-mutate-capture
                   :parent "cap-body-parent"
                   :headline "New Task"
                   :body "Some body text here.")))
      (should (plist-get result :id))
      (let ((entry (org-mcp-query-get-entry (plist-get result :id))))
        (should (string-match-p "Some body text here" (plist-get entry :body)))))))

(ert-deftest org-mcp-mutate-validate-drawer-name ()
  "Drawer name must be alphanumeric, no newlines or reserved names."
  (org-mcp-test-with-temp-org
      "* TODO Task
:PROPERTIES:
:ID: mut-val-drawer
:END:
"
    (dolist (case '(("RESULTS"                success)
                    ("LOGBOOK"                success)
                    ("My-Drawer_1"            success)
                    ("END"                    error)
                    ("PROPERTIES"             error)
                    ("bad\nname"              error)
                    (":colon:"                error)
                    (""                       error)))
      (if (eq (nth 1 case) 'error)
          (should-error (org-mcp-mutate-append-body "mut-val-drawer" "text" (nth 0 case))
                        :type 'org-mcp-invalid-input)
        (org-mcp-mutate-append-body "mut-val-drawer" "text" (nth 0 case))))))

(ert-deftest org-mcp-mutate-capture-validates-state ()
  "Capture rejects state containing newlines."
  (org-mcp-test-with-temp-org
      "* Projects
:PROPERTIES:
:ID: cap-val-state
:END:
"
    (should-error (org-mcp-mutate-capture
                   :parent "cap-val-state"
                   :headline "Task"
                   :state "TODO\nINJECT")
                  :type 'org-mcp-invalid-input)))

(ert-deftest org-mcp-mutate-capture-validates-body ()
  "Capture rejects body that would corrupt org structure."
  (org-mcp-test-with-temp-org
      "* Projects
:PROPERTIES:
:ID: cap-val-body
:END:
"
    (should-error (org-mcp-mutate-capture
                   :parent "cap-val-body"
                   :headline "Task"
                   :body "* Injected heading")
                  :type 'org-mcp-invalid-input)))

(ert-deftest org-mcp-mutate-validate-body-multiline-heading ()
  "Body with heading after newline is rejected."
  (org-mcp-test-with-temp-org
      "* TODO Task
:PROPERTIES:
:ID: mut-val-body-ml
:END:
"
    (dolist (case '(("line one\n* Injected heading"     error)
                    ("line one\n** Deep heading"         error)
                    ("line one\nno heading here"         success)
                    ("line one\n  * not a heading"       success)))
      (if (eq (nth 1 case) 'error)
          (should-error (org-mcp-mutate-append-body "mut-val-body-ml" (nth 0 case))
                        :type 'org-mcp-invalid-input)
        (org-mcp-mutate-append-body "mut-val-body-ml" (nth 0 case))))))

(ert-deftest org-mcp-mutate-assign-ids-assigns-and-preserves ()
  "Assign ids to id-less headings, leave existing ids intact, return mapping."
  (let* ((dir (file-truename (make-temp-file "org-mcp-assign-" t)))
         (file (expand-file-name "plan.org" dir))
         (org-mcp-allowed-directories (list dir))
         (org-mcp--resolved-allowed-dirs nil))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TODO: TODO NEXT WAITING | DONE CANCELLED\n"
                    "* Plan\n"
                    "** Component A\n"
                    "*** TODO Task one\n"
                    "*** NEXT Task two\n"
                    ":PROPERTIES:\n:ID: preexisting-id\n:END:\n"
                    "*** WAITING Task three\n"
                    "*** DONE Task four\n"
                    "** Notes (no state)\n"
                    "*** Random non-task heading\n"))
          (let* ((result (org-mcp-mutate-assign-ids file))
                 (entries (plist-get result :entries)))
            ;; Only headings with a TODO-state keyword get ids — including
            ;; custom active states (NEXT, WAITING) and done states (DONE).
            ;; Plain headings (Plan, Component A, Notes, Random...) are skipped.
            (should (= (length entries) 4))
            (let ((headlines (mapcar (lambda (e) (plist-get e :headline)) entries)))
              (should (member "Task one" headlines))
              (should (member "Task two" headlines))
              (should (member "Task three" headlines))
              (should (member "Task four" headlines))
              (should-not (member "Plan" headlines))
              (should-not (member "Component A" headlines))
              (should-not (member "Notes (no state)" headlines))
              (should-not (member "Random non-task heading" headlines)))
            (dolist (e entries)
              (should (stringp (plist-get e :id)))
              (should (> (length (plist-get e :id)) 0)))
            (should (seq-find (lambda (e) (equal (plist-get e :id) "preexisting-id"))
                              entries))
            ;; Idempotent: re-running assigns no new ids.
            (let* ((ids1 (sort (mapcar (lambda (e) (plist-get e :id)) entries) #'string<))
                   (entries2 (plist-get (org-mcp-mutate-assign-ids file) :entries))
                   (ids2 (sort (mapcar (lambda (e) (plist-get e :id)) entries2) #'string<)))
              (should (equal ids1 ids2)))))
      (when (get-file-buffer file) (kill-buffer (get-file-buffer file)))
      (delete-directory dir t))))

(ert-deftest org-mcp-mutate-assign-ids-denies-outside-allowed ()
  "Files outside allowed directories raise `org-mcp-access-denied'."
  (let* ((dir (file-truename (make-temp-file "org-mcp-assign-denied-" t)))
         (file (expand-file-name "plan.org" dir))
         (org-mcp-allowed-directories nil)
         (org-mcp--resolved-allowed-dirs nil)
         (org-agenda-files nil))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Plan\n"))
          (should-error (org-mcp-mutate-assign-ids file)
                        :type 'org-mcp-access-denied))
      (when (get-file-buffer file) (kill-buffer (get-file-buffer file)))
      (delete-directory dir t))))

(provide 'org-mcp-mutate-test)
;;; org-mcp-mutate-test.el ends here
