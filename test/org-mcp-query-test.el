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
      (should (equal (plist-get result :headline) "Implement auth"))
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
      (should (equal (plist-get (car ancestors) :headline) "Sprint 1"))
      (should (equal (plist-get (cadr ancestors) :headline) "Project Alpha")))))

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

(ert-deftest org-mcp-query-basic ()
  "Query entries matching an org-ql sexp."
  (org-mcp-test-with-temp-org
      "* TODO Task A :backend:
:PROPERTIES:
:ID: q-a
:END:
* DONE Task B :frontend:
:PROPERTIES:
:ID: q-b
:END:
* TODO Task C :backend:
:PROPERTIES:
:ID: q-c
:END:
"
    (let ((result (org-mcp-query-query '(and (todo "TODO") (tags "backend")) nil nil)))
      (should (= (plist-get result :count) 2))
      (should (= (length (plist-get result :entries)) 2)))))

(ert-deftest org-mcp-query-with-columns ()
  "Query with specific columns returns only those fields."
  (org-mcp-test-with-temp-org
      "* TODO Task A
:PROPERTIES:
:ID: qc-a
:EFFORT: 1h
:END:
"
    (let* ((result (org-mcp-query-query '(todo "TODO") nil '("id" "headline" "state" "properties")))
           (entry (car (plist-get result :entries))))
      (should (plist-get entry :id))
      (should (plist-get entry :headline))
      (should (plist-get entry :state))
      (should (plist-get entry :properties)))))

(ert-deftest org-mcp-query-default-columns ()
  "Default columns are id, headline, state."
  (org-mcp-test-with-temp-org
      "* TODO Task A
:PROPERTIES:
:ID: qd-a
:END:
"
    (let* ((result (org-mcp-query-query '(todo "TODO") nil nil))
           (entry (car (plist-get result :entries))))
      (should (plist-get entry :id))
      (should (plist-get entry :headline))
      (should (plist-get entry :state))
      (should-not (plist-get entry :properties)))))

(ert-deftest org-mcp-query-get-children ()
  "Get immediate children of an entry."
  (org-mcp-test-with-temp-org
      "* Project Alpha
:PROPERTIES:
:ID: parent-1
:END:
** TODO Subtask A
:PROPERTIES:
:ID: child-a
:END:
** DONE Subtask B
:PROPERTIES:
:ID: child-b
:END:
*** Nested under B
:PROPERTIES:
:ID: grandchild
:END:
"
    (let ((result (org-mcp-query-get-children "parent-1")))
      ;; Only immediate children, not grandchildren
      (should (= (length (plist-get result :children)) 2))
      (let ((first (car (plist-get result :children))))
        (should (equal (plist-get first :headline) "Subtask A"))
        (should (equal (plist-get first :state) "TODO"))))))

(ert-deftest org-mcp-query-get-properties-basic ()
  "Get properties for an entry without inheritance."
  (org-mcp-test-with-temp-org
      "* Parent
:PROPERTIES:
:ID: prop-parent
:CATEGORY: work
:EFFORT: 4h
:END:
** Child
:PROPERTIES:
:ID: prop-child
:ASSIGNEE: alice
:END:
"
    (let ((result (org-mcp-query-get-properties "prop-child")))
      (should (equal (plist-get (plist-get result :properties) :ASSIGNEE) "alice"))
      ;; Without inheritance, parent's EFFORT should not appear
      (should-not (plist-get (plist-get result :properties) :EFFORT)))))

(ert-deftest org-mcp-query-get-properties-inherited ()
  "Get properties with inheritance enabled."
  (org-mcp-test-with-temp-org
      "* Parent
:PROPERTIES:
:ID: inh-parent
:EFFORT: 4h
:END:
** Child
:PROPERTIES:
:ID: inh-child
:ASSIGNEE: alice
:END:
"
    (let ((result (org-mcp-query-get-properties "inh-child" t)))
      (should (equal (plist-get (plist-get result :properties) :ASSIGNEE) "alice"))
      ;; With inheritance, parent's EFFORT should appear
      (should (equal (plist-get (plist-get result :properties) :EFFORT) "4h")))))

(provide 'org-mcp-query-test)
;;; org-mcp-query-test.el ends here
