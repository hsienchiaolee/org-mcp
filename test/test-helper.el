;;; test-helper.el --- Shared test utilities -*- lexical-binding: t; -*-

(require 'ert)
(require 'json)
(require 'org)
(require 'org-id)

;; Redirect org-id-locations to a temp file for CI environments
(setq org-id-locations-file (expand-file-name "org-id-locations" temporary-file-directory))

(defmacro org-mcp-test-with-temp-org (contents &rest body)
  "Create a temp org file with CONTENTS, execute BODY in that buffer.
The file is registered with `org-agenda-files' for the duration."
  (declare (indent 1))
  `(let ((temp-file (make-temp-file "org-mcp-test-" nil ".org")))
     (unwind-protect
         (progn
           (with-current-buffer (find-file-noselect temp-file)
             (insert ,contents)
             (save-buffer)
             (org-mode))
           (let ((org-agenda-files (list temp-file)))
             ,@body))
       (when (get-file-buffer temp-file)
         (kill-buffer (get-file-buffer temp-file)))
       (delete-file temp-file))))

(defun org-mcp-test-parse-json (string)
  "Parse JSON STRING to plist."
  (json-parse-string string :object-type 'plist :null-object nil))

(defun org-mcp-test-make-request (method params &optional id)
  "Build a JSON-RPC request string."
  (json-serialize
   `(:jsonrpc "2.0"
     :id ,(or id 1)
     :method ,method
     :params ,params)))

(provide 'test-helper)
;;; test-helper.el ends here
