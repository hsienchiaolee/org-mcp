;;; org-mcp-mutate.el --- Mutation tools for org-mcp -*- lexical-binding: t; -*-

;;; Commentary:

;; Implements write tools: org_set_state, org_set_property.

;;; Code:

(require 'org)
(require 'org-id)
(require 'org-mcp-query)

(defun org-mcp-mutate-set-state (id state)
  "Set TODO state of entry ID to STATE. Pass nil to clear.
Returns plist with :id, :old_state, :new_state."
  (let ((location (org-mcp-query--find-entry id)))
    (with-current-buffer (find-file-noselect (car location))
      (org-with-wide-buffer
       (goto-char (cdr location))
       (let ((old-state (org-get-todo-state)))
         (org-todo (or state ""))
         (save-buffer)
         (list :id id
               :old_state old-state
               :new_state (org-get-todo-state)))))))

(defun org-mcp-mutate-set-property (id key value)
  "Set property KEY to VALUE on entry ID. Pass nil VALUE to delete.
Returns plist with :id, :key, :value."
  (let ((location (org-mcp-query--find-entry id)))
    (with-current-buffer (find-file-noselect (car location))
      (org-with-wide-buffer
       (goto-char (cdr location))
       (if value
           (org-set-property key value)
         (org-delete-property key))
       (save-buffer)
       (list :id id
             :key key
             :value value)))))

(provide 'org-mcp-mutate)
;;; org-mcp-mutate.el ends here
