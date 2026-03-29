;;; org-mcp-log.el --- Audit logging for org-mcp -*- lexical-binding: t; -*-

;;; Commentary:

;; Append-only file logging for mutation tool calls.

;;; Code:

(defcustom org-mcp-log-file nil
  "File path to append mutation log entries to.
When nil, logging is disabled."
  :type '(choice (const :tag "Disabled" nil)
                 (file :tag "Log file"))
  :group 'org-mcp)

(defconst org-mcp-log--mutation-tools
  '("org_set_state" "org_set_property" "org_set_headline"
    "org_append_body" "org_capture")
  "Tool names that are mutations and should be logged.")

(defun org-mcp-log (tool-name args)
  "Log TOOL-NAME call with ARGS to `org-mcp-log-file' if enabled.
Only mutation tools are logged."
  (when (and org-mcp-log-file
             (member tool-name org-mcp-log--mutation-tools))
    (let ((entry (format "[%s] %s %s\n"
                         (format-time-string "%Y-%m-%d %H:%M:%S")
                         tool-name
                         (json-serialize args))))
      (write-region entry nil org-mcp-log-file t 'silent))))

(provide 'org-mcp-log)
;;; org-mcp-log.el ends here
