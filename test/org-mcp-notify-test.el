;;; org-mcp-notify-test.el --- Tests for notification layer -*- lexical-binding: t; -*-

(require 'test-helper)
(require 'org-mcp-notify)
(require 'org-mcp-rpc)

(ert-deftest org-mcp-notify-state-change ()
  "State change hook emits entry_state_changed notification."
  (let ((notifications nil))
    (cl-letf (((symbol-function 'org-mcp-rpc-send)
               (lambda (msg) (push msg notifications))))
      (org-mcp-test-with-temp-org
          "* TODO Notify test
:PROPERTIES:
:ID: notify-state-1
:END:
"
        (org-mcp-notify-enable)
        (with-current-buffer (find-file-noselect
                              (car (org-id-find "notify-state-1")))
          (org-with-wide-buffer
           (goto-char (cdr (org-id-find "notify-state-1")))
           (org-todo "DONE")))
        (org-mcp-notify-disable)))
    (should (>= (length notifications) 1))
    (let* ((parsed (org-mcp-test-parse-json (car notifications)))
           (params (plist-get parsed :params)))
      (should (equal (plist-get parsed :method) "entry_state_changed"))
      (should (equal (plist-get params :id) "notify-state-1"))
      (should (equal (plist-get params :old_state) "TODO"))
      (should (equal (plist-get params :new_state) "DONE")))))

(ert-deftest org-mcp-notify-property-changed ()
  "Property change emits property_changed notification."
  (let ((notifications nil))
    (cl-letf (((symbol-function 'org-mcp-rpc-send)
               (lambda (msg) (push msg notifications))))
      (org-mcp-notify-enable)
      (org-mcp-notify-emit-property-changed "test-id" "ASSIGNEE" nil "agent-1")
      (org-mcp-notify-disable))
    (should (= (length notifications) 1))
    (let* ((parsed (org-mcp-test-parse-json (car notifications)))
           (params (plist-get parsed :params)))
      (should (equal (plist-get parsed :method) "property_changed"))
      (should (equal (plist-get params :key) "ASSIGNEE"))
      (should (equal (plist-get params :new_value) "agent-1")))))

(ert-deftest org-mcp-notify-entry-created ()
  "Entry creation emits entry_created notification."
  (let ((notifications nil))
    (cl-letf (((symbol-function 'org-mcp-rpc-send)
               (lambda (msg) (push msg notifications))))
      (org-mcp-notify-enable)
      (org-mcp-notify-emit-entry-created "new-id" "/path/file.org" "New task" "TODO")
      (org-mcp-notify-disable))
    (should (= (length notifications) 1))
    (let* ((parsed (org-mcp-test-parse-json (car notifications)))
           (params (plist-get parsed :params)))
      (should (equal (plist-get parsed :method) "entry_created"))
      (should (equal (plist-get params :id) "new-id")))))

(provide 'org-mcp-notify-test)
;;; org-mcp-notify-test.el ends here
