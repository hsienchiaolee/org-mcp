;;; org-mcp-mutate.el --- Mutation tools for org-mcp -*- lexical-binding: t; -*-

;; URL: https://github.com/hsienchiaolee/org-mcp

;;; Commentary:

;; Implements write tools: org_set_state, org_set_property.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'org-mcp-query)
(require 'org-mcp-access)

(define-error 'org-mcp-invalid-input "Invalid input")

(defun org-mcp-mutate--validate-headline (text)
  "Signal `org-mcp-invalid-input' if TEXT is not a valid headline."
  (when (or (string-empty-p text)
            (string-blank-p text)
            (string-match-p "\n" text)
            (string-match-p "^\\*" text))
    (signal 'org-mcp-invalid-input (list "Invalid headline"))))

(defun org-mcp-mutate--validate-property-key (key)
  "Signal `org-mcp-invalid-input' if KEY is not a valid property name."
  (when (or (string-empty-p key)
            (string-blank-p key)
            (string-match-p "\n" key))
    (signal 'org-mcp-invalid-input (list "Invalid property key"))))

(defun org-mcp-mutate--validate-drawer-name (name)
  "Signal `org-mcp-invalid-input' if NAME is not a valid drawer name."
  (when (or (string-empty-p name)
            (not (string-match-p "\\`[A-Za-z][A-Za-z0-9_-]*\\'" name))
            (member (upcase name) '("END" "PROPERTIES")))
    (signal 'org-mcp-invalid-input (list "Invalid drawer name"))))

(defun org-mcp-mutate--validate-body (text)
  "Signal `org-mcp-invalid-input' if TEXT would corrupt org structure."
  (when (string-match-p "^\\*+ " text)
    (signal 'org-mcp-invalid-input (list "Body contains org heading")))
  (let ((begins 0) (ends 0) (start 0))
    (while (string-match "#\\+BEGIN_" text start)
      (setq begins (1+ begins) start (match-end 0)))
    (setq start 0)
    (while (string-match "#\\+END_" text start)
      (setq ends (1+ ends) start (match-end 0)))
    (unless (= begins ends)
      (signal 'org-mcp-invalid-input (list "Unbalanced #+BEGIN/#+END blocks")))))

(defun org-mcp-mutate-set-state (id state)
  "Set TODO state of entry ID to STATE. Pass nil to clear.
Returns plist with :id, :old_state, :new_state.
State validation is handled by `org-todo' which signals an error for
invalid keywords."
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
  (org-mcp-mutate--validate-property-key key)
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

(defun org-mcp-mutate-set-headline (id headline)
  "Set headline of entry ID to HEADLINE.
Returns plist with :id, :old_headline, :new_headline."
  (org-mcp-mutate--validate-headline headline)
  (let ((location (org-mcp-query--find-entry id)))
    (with-current-buffer (find-file-noselect (car location))
      (org-with-wide-buffer
       (goto-char (cdr location))
       (let ((old-headline (org-get-heading t t t t)))
         (org-edit-headline headline)
         (save-buffer)
         (list :id id
               :old_headline old-headline
               :new_headline headline))))))

(defun org-mcp-mutate-append-body (id text &optional drawer)
  "Append TEXT to the body of entry ID.
If DRAWER is non-nil, append inside that named drawer (created if needed)."
  (org-mcp-mutate--validate-body text)
  (when drawer (org-mcp-mutate--validate-drawer-name drawer))
  (let ((location (org-mcp-query--find-entry id)))
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

(cl-defun org-mcp-mutate-capture (&key file parent headline state properties body template-key)
  "Create a new Org entry.
If PARENT (org-id) is given, file under it.
If only FILE is given, append as top-level entry.
HEADLINE is always required."
  (when template-key
    (error "Template-based capture not yet implemented"))
  (unless headline
    (error "Headline is required"))
  (org-mcp-mutate--validate-headline headline)
  (when (and state (string-match-p "\n" state))
    (signal 'org-mcp-invalid-input (list "State must not contain newlines")))
  (when body
    (org-mcp-mutate--validate-body body))
  (unless (or parent file)
    (error "Either parent or file is required"))
  (when file
    (org-mcp-check-access file))
  (if parent
      (let ((location (org-mcp-query--find-entry parent)))
        (with-current-buffer (find-file-noselect (car location))
          (org-with-wide-buffer
           (goto-char (cdr location))
           (let ((parent-level (org-current-level)))
             (org-end-of-subtree t)
             (insert "\n" (make-string (1+ parent-level) ?*) " "
                     (if state (concat state " ") "")
                     headline "\n")
             (org-mcp-mutate--finalize-capture state properties body)))))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (goto-char (point-max))
       (insert (if (bolp) "" "\n") "* "
               (if state (concat state " ") "")
               headline "\n")
       (org-mcp-mutate--finalize-capture state properties body)))))

(defun org-mcp-mutate--finalize-capture (_state properties body)
  "Finalize a captured entry at point: assign ID, set PROPERTIES, insert BODY."
  (let ((new-id (org-id-get-create)))
    (when properties
      (cl-loop for (key val) on properties by #'cddr
               do (org-set-property (substring (symbol-name key) 1) val)))
    (when body
      (org-end-of-meta-data t)
      (insert body "\n"))
    (save-buffer)
    (list :id new-id :file (buffer-file-name))))

(provide 'org-mcp-mutate)
;;; org-mcp-mutate.el ends here
