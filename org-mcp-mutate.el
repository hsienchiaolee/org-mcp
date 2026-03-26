;;; org-mcp-mutate.el --- Mutation tools for org-mcp -*- lexical-binding: t; -*-

;; URL: https://github.com/hsienchiaolee/org-mcp

;;; Commentary:

;; Implements write tools: org_set_state, org_set_property.

;;; Code:

(require 'cl-lib)
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

(defun org-mcp-mutate-append-body (id text &optional drawer)
  "Append TEXT to the body of entry ID.
If DRAWER is non-nil, append inside that named drawer (created if needed)."
  (let ((location (org-id-find id)))
    (unless location
      (signal 'org-mcp-entry-not-found (list id)))
    (with-current-buffer (find-file-noselect (car location))
      (org-with-wide-buffer
       (goto-char (cdr location))
       (if drawer
           (org-mcp-mutate--append-to-drawer drawer text)
         (org-mcp-mutate--append-to-body text))
       (save-buffer)
       (list :id id :appended t)))))

(defun org-mcp-mutate--append-to-body (text)
  "Append TEXT to the body of the entry at point."
  (org-end-of-meta-data t)
  (outline-next-heading)
  (unless (eobp) (forward-char -1))
  (insert (if (bolp) "" "\n") text "\n"))

(defun org-mcp-mutate--append-to-drawer (drawer-name text)
  "Append TEXT inside DRAWER-NAME drawer at the entry at point.
Create the drawer if it does not exist."
  (org-end-of-meta-data t)
  (let ((drawer-re (format "^[ \t]*:%s:[ \t]*$" (regexp-quote drawer-name)))
        (found nil))
    (save-excursion
      (let ((limit (save-excursion (outline-next-heading) (point))))
        (when (re-search-forward drawer-re limit t)
          (setq found t)
          (re-search-forward "^[ \t]*:END:[ \t]*$" limit t)
          (beginning-of-line)
          (insert text "\n"))))
    (unless found
      (insert ":" drawer-name ":\n" text "\n:END:\n"))))

(cl-defun org-mcp-mutate-capture (&key file headline heading state properties body template-key)
  "Create a new Org entry.
If TEMPLATE-KEY is provided, use that capture template.
Otherwise, create from inline params under HEADLINE in FILE."
  (if template-key
      (error "Template-based capture not yet implemented")
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (goto-char (point-min))
       (unless (re-search-forward
                (format org-complex-heading-regexp-format (regexp-quote headline))
                nil t)
         (signal 'org-mcp-entry-not-found (list headline)))
       (let ((parent-level (org-current-level)))
         (org-end-of-subtree t)
         (insert "\n" (make-string (1+ parent-level) ?*) " "
                 (if state (concat state " ") "")
                 heading "\n")
         (let ((new-id (org-id-get-create)))
           (when properties
             (dolist (pair properties)
               (org-set-property (car pair) (cdr pair))))
           (when body
             (org-end-of-meta-data t)
             (insert body "\n"))
           (save-buffer)
           (list :id new-id :file file)))))))

(provide 'org-mcp-mutate)
;;; org-mcp-mutate.el ends here
