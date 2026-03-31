;;; org-mcp-rpc.el --- JSON-RPC 2.0 layer for org-mcp -*- lexical-binding: t; -*-

;; URL: https://github.com/hsienchiaolee/org-mcp

;;; Commentary:

;; Handles JSON-RPC 2.0 message parsing, validation, and serialization.
;; All messages are newline-delimited JSON over stdio.

;;; Code:

(require 'json)

;; Error types
(define-error 'org-mcp-rpc-parse-error "JSON parse error" 'json-error)
(define-error 'org-mcp-rpc-invalid-request "Invalid JSON-RPC request")
(define-error 'org-mcp-entry-not-found "Entry not found")

;; Standard JSON-RPC 2.0 error codes
(defconst org-mcp-rpc-error-parse -32700)
(defconst org-mcp-rpc-error-invalid-request -32600)
(defconst org-mcp-rpc-error-method-not-found -32601)
(defconst org-mcp-rpc-error-invalid-params -32602)
(defconst org-mcp-rpc-error-internal -32603)

(defun org-mcp-rpc-parse (string)
  "Parse JSON-RPC 2.0 message STRING. Return plist.
Signal `org-mcp-rpc-parse-error' for malformed JSON.
Signal `org-mcp-rpc-invalid-request' if jsonrpc field is missing or wrong."
  (let ((msg (condition-case _err
                 (json-parse-string string :object-type 'plist :null-object nil)
               (json-error (signal 'org-mcp-rpc-parse-error (list string))))))
    (unless (equal (plist-get msg :jsonrpc) "2.0")
      (signal 'org-mcp-rpc-invalid-request (list "missing or invalid jsonrpc field")))
    msg))

(defun org-mcp-rpc-format-result (id result)
  "Format a JSON-RPC 2.0 success response for ID with RESULT plist."
  (json-serialize `(:jsonrpc "2.0" :id ,id :result ,result)))

(defun org-mcp-rpc-format-error (id code message &optional data)
  "Format a JSON-RPC 2.0 error response for ID.
CODE is an integer error code, MESSAGE a string.
DATA is an optional plist with additional info."
  (let ((err `(:code ,code :message ,message)))
    (when data
      (setq err (plist-put err :data data)))
    (json-serialize `(:jsonrpc "2.0" :id ,id :error ,err))))

(defun org-mcp-rpc-format-notification (method params)
  "Format a JSON-RPC 2.0 notification (no id) with METHOD and PARAMS."
  (json-serialize `(:jsonrpc "2.0" :method ,method :params ,params)))

(defun org-mcp-rpc-send (string)
  "Write STRING followed by newline to stdout."
  (princ string)
  (princ "\n"))


(provide 'org-mcp-rpc)
;;; org-mcp-rpc.el ends here
