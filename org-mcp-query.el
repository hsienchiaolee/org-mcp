;;; org-mcp-query.el --- Query tools for org-mcp -*- lexical-binding: t; -*-

;; URL: https://github.com/hsienchiaolee/org-mcp

;;; Commentary:

;; Implements read-only tools: org_get_entry, org_query, org_get_children,
;; org_get_properties.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'org-element)
(require 'org-mcp-rpc)
(require 'org-mcp-access)

(defun org-mcp-query--find-entry (id)
  "Find entry by org-id ID. Return (file . position) or signal error."
  (let ((location (org-id-find id)))
    (unless location
      (signal 'org-mcp-entry-not-found (list id)))
    (org-mcp-check-access (car location))
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
          ;; Skip past planning lines and property drawer (in Org order)
          (when (looking-at org-planning-line-re)
            (forward-line))
          (when (looking-at org-property-drawer-re)
            (goto-char (match-end 0))
            (forward-line))
          (let ((body-start (point)))
            (string-trim
             (buffer-substring-no-properties body-start contents-end))))))))

(defun org-mcp-query--get-ancestors ()
  "Get ancestor entries from parent to root for entry at point."
  (let ((ancestors nil))
    (save-excursion
      (while (org-up-heading-safe)
        (push (list :headline (substring-no-properties (org-get-heading t t t t))
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
             :headline (substring-no-properties (org-get-heading t t t t))
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

(defconst org-mcp-query-default-columns '("id" "headline" "state")
  "Default columns returned by org_query.")

(defun org-mcp-query--project-entry (columns)
  "Return a function that projects an entry at point to a plist with COLUMNS."
  (lambda ()
    (let ((result nil))
      (dolist (col columns)
        (pcase col
          ("id" (setq result (plist-put result :id (org-id-get))))
          ("headline" (setq result (plist-put result :headline
                                              (substring-no-properties (org-get-heading t t t t)))))
          ("state" (setq result (plist-put result :state (org-get-todo-state))))
          ("tags" (setq result (plist-put result :tags (org-mcp-query--get-tags))))
          ("properties" (setq result (plist-put result :properties (org-mcp-query--get-properties))))
          ("priority" (setq result (plist-put result :priority
                                              (let ((p (org-entry-get nil "PRIORITY")))
                                                (when p (string-to-char p))))))
          ("file" (setq result (plist-put result :file (buffer-file-name))))
          ("body" (setq result (plist-put result :body (org-mcp-query--get-body))))
          ("ancestors" (setq result (plist-put result :ancestors (org-mcp-query--get-ancestors))))
          ("scheduled" (setq result (plist-put result :scheduled (org-mcp-query--get-timestamp :scheduled))))
          ("deadline" (setq result (plist-put result :deadline (org-mcp-query--get-timestamp :deadline))))
          ("closed" (setq result (plist-put result :closed (org-mcp-query--get-timestamp :closed))))
          ("level" (setq result (plist-put result :level (org-current-level))))))
      result)))

(defun org-mcp-query--compile (query)
  "Compile a query sexp into a predicate function.
Supports: (todo STATE...), (tags TAG), (priority VAL),
\(property KEY VAL), (headline REGEXP), (scheduled), (deadline),
\(and ...), (or ...), (not PRED)."
  (pcase query
    (`(and . ,preds)
     (let ((compiled (mapcar #'org-mcp-query--compile preds)))
       (lambda () (seq-every-p #'funcall compiled))))
    (`(or . ,preds)
     (let ((compiled (mapcar #'org-mcp-query--compile preds)))
       (lambda () (seq-some #'funcall compiled))))
    (`(not ,pred)
     (let ((compiled (org-mcp-query--compile pred)))
       (lambda () (not (funcall compiled)))))
    (`(todo . ,states)
     (lambda () (member (org-get-todo-state) states)))
    (`(tags ,tag)
     (lambda () (member tag (org-get-tags nil t))))
    (`(priority ,val)
     (lambda () (equal (org-entry-get nil "PRIORITY") val)))
    (`(property ,key ,val)
     (lambda () (equal (org-entry-get nil key) val)))
    (`(headline ,regexp)
     (lambda () (string-match-p regexp (org-get-heading t t t t))))
    (`(scheduled)
     (lambda () (org-entry-get nil "SCHEDULED")))
    (`(deadline)
     (lambda () (org-entry-get nil "DEADLINE")))
    (_ (error "Unknown query predicate: %S" query))))

(defun org-mcp-query--select (files predicate action)
  "Map over entries in FILES, collect ACTION results where PREDICATE matches."
  (let ((results nil))
    (dolist (file files)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (while (re-search-forward org-heading-regexp nil t)
           (beginning-of-line)
           (when (funcall predicate)
             (push (funcall action) results))
           (end-of-line)))))
    (nreverse results)))

(defun org-mcp-query-query (query &optional files columns)
  "Run QUERY sexp across FILES (default `org-agenda-files').
COLUMNS controls which fields are returned per entry.
If COLUMNS is nil, use `org-mcp-query-default-columns'.
If COLUMNS is the string \"all\", return full entry data."
  (let* ((files (seq-filter (lambda (f) (condition-case nil
                                              (org-mcp-check-access f)
                                            (org-mcp-access-denied nil)))
                            (or files (org-agenda-files))))
         (cols (cond
                ((equal columns "all") '("id" "headline" "state" "tags" "properties"
                                         "priority" "file" "body" "ancestors"
                                         "scheduled" "deadline" "closed" "level"))
                ((null columns) org-mcp-query-default-columns)
                (t columns)))
         (predicate (org-mcp-query--compile query))
         (entries (org-mcp-query--select files predicate
                    (org-mcp-query--project-entry cols))))
    (list :count (length entries)
          :entries entries)))

(defun org-mcp-query-get-children (id &optional columns)
  "Return immediate child entries of org-id ID.
COLUMNS controls which fields are returned (default: id, headline, state)."
  (let ((location (org-mcp-query--find-entry id))
        (cols (or columns org-mcp-query-default-columns)))
    (with-current-buffer (find-file-noselect (car location))
      (org-with-wide-buffer
       (goto-char (cdr location))
       (let ((parent-level (org-current-level))
             (children nil)
             (project (org-mcp-query--project-entry cols)))
         (when (org-goto-first-child)
           (push (funcall project) children)
           (while (org-get-next-sibling)
             (when (= (org-current-level) (1+ parent-level))
               (push (funcall project) children))))
         (list :children (nreverse children)))))))

(defun org-mcp-query-get-properties (id &optional inherited)
  "Return property drawer for org-id ID.
When INHERITED is non-nil, include properties inherited from ancestors."
  (let ((location (org-mcp-query--find-entry id)))
    (with-current-buffer (find-file-noselect (car location))
      (org-with-wide-buffer
       (goto-char (cdr location))
       (if (not inherited)
           (list :properties (org-mcp-query--get-properties))
         ;; Collect all property keys from this entry and ancestors
         (let ((keys nil))
           (dolist (pair (org-entry-properties nil 'standard))
             (cl-pushnew (car pair) keys :test #'equal))
           (save-excursion
             (while (org-up-heading-safe)
               (dolist (pair (org-entry-properties nil 'standard))
                 (cl-pushnew (car pair) keys :test #'equal))))
           ;; Fetch each key with inheritance, filtering standard props
           (let ((result nil))
             (dolist (key keys)
               (unless (member key '("CATEGORY" "FILE" "BLOCKED" "ITEM"
                                     "PRIORITY" "TODO" "TAGS" "ALLTAGS"
                                     "CLOCKSUM" "CLOSED" "DEADLINE" "SCHEDULED"
                                     "TIMESTAMP" "TIMESTAMP_IA"))
                 (let ((val (org-entry-get nil key t)))
                   (when val
                     (setq result (plist-put result (intern (concat ":" key)) val))))))
             (list :properties result))))))))

(defun org-mcp-query--parse-todo-sequence (line)
  "Parse a TODO keyword LINE string into a plist with :active and :done."
  (let* ((parts (split-string line "|"))
         (active (split-string (string-trim (car parts))))
         (done (when (cdr parts) (split-string (string-trim (cadr parts))))))
    (list :active (vconcat active) :done (vconcat done))))

(defun org-mcp-query-get-config (&optional file)
  "Return TODO keywords and tags for FILE (or first agenda file)."
  (let ((f (or file (car (org-agenda-files)))))
    (org-mcp-check-access f)
    (with-current-buffer (find-file-noselect f)
      (let* ((collected (org-collect-keywords '("TODO" "SEQ_TODO" "TYP_TODO" "TAGS")))
             (todo-lines (mapcar #'cadr (seq-filter (lambda (e) (member (car e) '("TODO" "SEQ_TODO" "TYP_TODO"))) collected)))
             (tag-lines (mapcar #'cadr (seq-filter (lambda (e) (equal (car e) "TAGS")) collected)))
             (keywords (if todo-lines
                           (mapcar #'org-mcp-query--parse-todo-sequence todo-lines)
                         (mapcar (lambda (e)
                                   (org-mcp-query--parse-todo-sequence
                                    (mapconcat #'identity (cdr e) " ")))
                                 (seq-filter #'listp org-todo-keywords))))
             (tags (if tag-lines
                       (mapcan (lambda (l) (split-string (string-trim l))) tag-lines)
                     (mapcar #'car (seq-filter (lambda (e) (stringp (car e))) org-tag-alist)))))
        (list :todo_keywords (vconcat keywords)
              :tags (vconcat tags)
              :file f)))))

(defun org-mcp-query-list-files ()
  "Return the list of agenda files, filtered by access control."
  (list :files (vconcat (seq-filter (lambda (f) (condition-case nil
                                                    (org-mcp-check-access f)
                                                  (org-mcp-access-denied nil)))
                                    (org-agenda-files)))))

(provide 'org-mcp-query)
;;; org-mcp-query.el ends here
