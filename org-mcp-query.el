;;; org-mcp-query.el --- Query tools for org-mcp -*- lexical-binding: t; -*-

;;; Commentary:

;; Implements read-only tools: org_get_entry, org_query, org_get_children,
;; org_get_properties.

;;; Code:

(require 'org)
(require 'org-id)
(require 'org-element)

(define-error 'org-mcp-entry-not-found "Entry not found")

(defun org-mcp-query--find-entry (id)
  "Find entry by org-id ID. Return (file . position) or signal error."
  (let ((location (org-id-find id)))
    (unless location
      (signal 'org-mcp-entry-not-found (list id)))
    location))

(defun org-mcp-query--get-tags ()
  "Get tags for entry at point, excluding inherited tags."
  (let ((tags (org-get-tags nil t)))
    (when tags (mapcar #'substring-no-properties tags))))

(defun org-mcp-query--get-properties ()
  "Get property drawer as a plist for entry at point.
Excludes standard Org properties (ID, CATEGORY, etc.)."
  (let* ((all-props (org-entry-properties nil 'standard))
         (result nil))
    (dolist (pair all-props)
      (unless (member (car pair) '("CATEGORY" "FILE" "BLOCKED" "ITEM"
                                    "PRIORITY" "TODO" "TAGS" "ALLTAGS"
                                    "CLOCKSUM" "CLOSED" "DEADLINE" "SCHEDULED"
                                    "TIMESTAMP" "TIMESTAMP_IA"))
        (setq result (plist-put result (intern (concat ":" (car pair))) (cdr pair)))))
    result))

(defun org-mcp-query--get-body ()
  "Get body text of entry at point, excluding property drawer and planning."
  (let ((element (org-element-at-point)))
    (let ((contents-begin (org-element-property :contents-begin element))
          (contents-end (org-element-property :contents-end element)))
      (when (and contents-begin contents-end)
        (save-excursion
          (goto-char contents-begin)
          ;; Skip past property drawer and planning lines
          (when (looking-at org-property-drawer-re)
            (goto-char (match-end 0))
            (forward-line))
          (when (looking-at org-planning-line-re)
            (forward-line))
          (let ((body-start (point)))
            (string-trim
             (buffer-substring-no-properties body-start contents-end))))))))

(defun org-mcp-query--get-ancestors ()
  "Get ancestor entries from parent to root for entry at point."
  (let ((ancestors nil))
    (save-excursion
      (while (org-up-heading-safe)
        (push (list :heading (substring-no-properties (org-get-heading t t t t))
                    :state (org-get-todo-state)
                    :properties (org-mcp-query--get-properties))
              ancestors)))
    (nreverse ancestors)))

(defun org-mcp-query--get-timestamp (type)
  "Get timestamp of TYPE (:scheduled, :deadline, :closed) as YYYY-MM-DD string."
  (let ((ts (org-element-property type (org-element-at-point))))
    (when ts
      (format "%04d-%02d-%02d"
              (org-element-property :year-start ts)
              (org-element-property :month-start ts)
              (org-element-property :day-start ts)))))

(defun org-mcp-query-get-entry (id)
  "Return full entry data for org-id ID as a plist."
  (let ((location (org-mcp-query--find-entry id)))
    (with-current-buffer (find-file-noselect (car location))
      (org-with-wide-buffer
       (goto-char (cdr location))
       (list :id id
             :file (buffer-file-name)
             :heading (substring-no-properties (org-get-heading t t t t))
             :state (org-get-todo-state)
             :priority (let ((p (org-entry-get nil "PRIORITY")))
                         (when p (string-to-char p)))
             :tags (org-mcp-query--get-tags)
             :properties (org-mcp-query--get-properties)
             :body (org-mcp-query--get-body)
             :ancestors (org-mcp-query--get-ancestors)
             :scheduled (org-mcp-query--get-timestamp :scheduled)
             :deadline (org-mcp-query--get-timestamp :deadline)
             :closed (org-mcp-query--get-timestamp :closed))))))

(provide 'org-mcp-query)
;;; org-mcp-query.el ends here
