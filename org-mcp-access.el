;;; org-mcp-access.el --- Access control for org-mcp -*- lexical-binding: t; -*-

;;; Commentary:

;; Directory-scoped access control for org-mcp tools.
;; All file paths are checked against `org-mcp-allowed-directories' before access.

;;; Code:

(require 'org)
(require 'url-util)

(defcustom org-mcp-allowed-directories nil
  "List of directory prefixes that org-mcp tools may access.
When nil, defaults to the directories containing `org-agenda-files'."
  :type '(repeat directory)
  :group 'org-mcp)

(defvar org-mcp--client-roots nil
  "List of local directory paths extracted from MCP initialize roots.")

(defvar org-mcp--resolved-allowed-dirs nil
  "Cached allowed directories computed at initialize time.")

(defun org-mcp-access-resolve-directories ()
  "Compute and cache the allowed directory set.
Union of `org-mcp--client-roots' and `org-mcp-allowed-directories',
falling back to `org-agenda-files' directories when both are nil.
Logs to stderr when falling back."
  (let ((dirs (append org-mcp--client-roots org-mcp-allowed-directories)))
    (unless dirs
      (message "org-mcp: no roots or allowed-directories configured, falling back to org-agenda-files")
      (setq dirs (delete-dups
                  (mapcar (lambda (f) (file-name-directory (file-truename f)))
                          (org-agenda-files)))))
    (setq org-mcp--resolved-allowed-dirs dirs)))

(define-error 'org-mcp-access-denied "File not in allowed directories")

(defun org-mcp-access--parse-file-uri (uri)
  "Convert a file:// URI to a local path. Return nil for non-file URIs."
  (when (and uri (stringp uri) (string-prefix-p "file:///" uri))
    (url-unhex-string (substring uri 7))))

(defun org-mcp-check-access (file-path)
  "Signal `org-mcp-access-denied' if FILE-PATH is not under an allowed directory.
Returns t if access is permitted."
  (let* ((real-path (file-truename file-path))
         (allowed (or org-mcp-allowed-directories
                      (mapcar (lambda (f) (file-name-directory (file-truename f)))
                              (org-agenda-files)))))
    (unless (seq-some (lambda (dir)
                        (string-prefix-p (file-truename (expand-file-name dir))
                                         real-path))
                      allowed)
      (signal 'org-mcp-access-denied (list file-path)))
    t))

(provide 'org-mcp-access)
;;; org-mcp-access.el ends here
