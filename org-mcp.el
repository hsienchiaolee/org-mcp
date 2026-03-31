;;; org-mcp.el --- MCP server for Org-mode -*- lexical-binding: t; -*-

;; Author: Kai Lee
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (org "9.6"))
;; Keywords: org, mcp
;; URL: https://github.com/hsienchiaolee/org-mcp

;;; Commentary:

;; A minimal MCP (Model Context Protocol) server that exposes Org-mode's
;; data model over stdio JSON-RPC 2.0.

;;; Code:

(require 'org-mcp-rpc)
(require 'org-mcp-access)
(require 'org-mcp-query)
(require 'org-mcp-mutate)
(require 'org-mcp-notify)
(require 'org-mcp-log)

(defvar org-mcp--initialized nil
  "Non-nil after successful initialize handshake.")

(defconst org-mcp--version "0.1.0")

(defconst org-mcp--tool-definitions
  `((:name "org_get_entry"
     :description "Return full data for a single Org entry by its org-id."
     :inputSchema (:type "object"
                   :properties (:id (:type "string" :description "The org-id of the entry"))
                   :required ["id"]))
    (:name "org_query"
     :description "Run a query across agenda files and return matching entries. Available columns: id, headline, state, tags, properties, priority, file, body, ancestors, scheduled, deadline, closed, level."
     :inputSchema (:type "object"
                   :properties (:query (:type "string" :description "Query s-expression as a string")
                                :files (:type "array" :items (:type "string") :description "Files to search; defaults to org-agenda-files")
                                :columns (:description "Columns to return per entry; defaults to [id, headline, state]"))
                   :required ["query"]))
    (:name "org_get_children"
     :description "Return immediate child entries of a given entry."
     :inputSchema (:type "object"
                   :properties (:id (:type "string" :description "The org-id of the parent entry")
                                :columns (:description "Columns to return per child"))
                   :required ["id"]))
    (:name "org_get_properties"
     :description "Return the property drawer for an entry."
     :inputSchema (:type "object"
                   :properties (:id (:type "string" :description "The org-id of the entry")
                                :inherited (:type "boolean" :description "Include inherited properties; defaults to false"))
                   :required ["id"]))
    (:name "org_set_headline"
     :description "Rename the headline of an entry."
     :inputSchema (:type "object"
                   :properties (:id (:type "string" :description "The org-id of the entry")
                                :headline (:type "string" :description "New headline text"))
                   :required ["id" "headline"]))
    (:name "org_set_state"
     :description "Set the TODO keyword of an entry."
     :inputSchema (:type "object"
                   :properties (:id (:type "string" :description "The org-id of the entry")
                                :state (:description "TODO keyword string or null to clear"))
                   :required ["id" "state"]))
    (:name "org_set_property"
     :description "Set or delete a property on an entry."
     :inputSchema (:type "object"
                   :properties (:id (:type "string" :description "The org-id of the entry")
                                :key (:type "string" :description "Property name")
                                :value (:description "Property value string or null to delete"))
                   :required ["id" "key" "value"]))
    (:name "org_append_body"
     :description "Append text to the body of an entry, optionally inside a named drawer."
     :inputSchema (:type "object"
                   :properties (:id (:type "string" :description "The org-id of the entry")
                                :text (:type "string" :description "Text to append")
                                :drawer (:type "string" :description "Optional drawer name"))
                   :required ["id" "text"]))
    (:name "org_capture"
     :description "Create a new Org entry. If parent org-id is given, file under it; otherwise append as top-level to file."
     :inputSchema (:type "object"
                   :properties (:file (:type "string" :description "Target file path (required when no parent)")
                                :parent (:type "string" :description "Org-id of parent entry to file under")
                                :headline (:type "string" :description "New entry headline")
                                :state (:type "string" :description "TODO keyword")
                                :properties (:type "object" :description "Property key-value pairs")
                                :body (:type "string" :description "Body text")
                                :template_key (:type "string" :description "Capture template key"))
                   :required ["headline"]))
    (:name "org_get_config"
     :description "Return TODO keyword sequences and tags for an agenda file."
     :inputSchema (:type "object"
                   :properties (:file (:type "string" :description "File path; defaults to first agenda file"))))
    (:name "org_list_files"
     :description "Return the list of org-agenda-files."
     :inputSchema (:type "object")))
  "MCP tool definitions with JSON Schema input specs.")

(defun org-mcp--handle-initialize (id _params)
  "Handle the initialize handshake. Return response plist."
  (setq org-mcp--initialized t)
  `(:jsonrpc "2.0" :id ,id
    :result (:protocolVersion "2025-03-26"
             :capabilities (:tools (:__placeholder t))
             :serverInfo (:name "org-mcp" :version ,org-mcp--version))))

(defun org-mcp--handle-tools-list (id)
  "Handle tools/list. Return list of available tools."
  `(:jsonrpc "2.0" :id ,id
    :result (:tools ,org-mcp--tool-definitions)))

(defun org-mcp--handle-tools-call (id params)
  "Handle tools/call. Dispatch to the appropriate handler."
  (let ((name (plist-get params :name))
        (args (plist-get params :arguments)))
    (condition-case err
        (let ((result (org-mcp--call-tool name args)))
          `(:jsonrpc "2.0" :id ,id :result ,result))
      (org-mcp-invalid-input
       `(:jsonrpc "2.0" :id ,id
         :error (:code ,org-mcp-rpc-error-invalid-params
                 :message ,(cadr err))))
      (org-mcp-access-denied
       `(:jsonrpc "2.0" :id ,id
         :error (:code ,org-mcp-rpc-error-invalid-params
                 :message "File not in allowed directories"
                 :data (:file ,(cadr err)))))
      (org-mcp-entry-not-found
       `(:jsonrpc "2.0" :id ,id
         :error (:code ,org-mcp-rpc-error-invalid-params
                 :message "Entry not found"
                 :data (:id ,(cadr err)))))
      (org-mcp-method-not-found
       `(:jsonrpc "2.0" :id ,id
         :error (:code ,org-mcp-rpc-error-method-not-found
                 :message ,(format "Unknown tool: %s" (cadr err)))))
      (error
       `(:jsonrpc "2.0" :id ,id
         :error (:code ,org-mcp-rpc-error-internal
                 :message ,(error-message-string err)))))))

(defconst org-mcp--safe-query-symbols
  '(and or not todo tags priority property headline scheduled deadline)
  "Symbols allowed in query s-expressions.")

(defun org-mcp--safe-read-query (string)
  "Read STRING as a query s-expression, rejecting unsafe forms.
Only allows lists, strings, numbers, and known query symbols."
  (let ((form (condition-case nil
                  (car (read-from-string string))
                (error (signal 'org-mcp-invalid-input
                               (list "Malformed query s-expression"))))))
    (org-mcp--validate-query-form form)
    form))

(defun org-mcp--validate-query-form (form)
  "Signal `org-mcp-invalid-input' if FORM contains unsafe elements."
  (cond
   ((stringp form) t)
   ((numberp form) t)
   ((and (symbolp form)
         (memq form org-mcp--safe-query-symbols)) t)
   ((symbolp form)
    (signal 'org-mcp-invalid-input
            (list (format "Unknown symbol in query: %S" form))))
   ((listp form)
    (dolist (elem form) (org-mcp--validate-query-form elem)))
   (t (signal 'org-mcp-invalid-input
              (list (format "Unsupported form in query: %S" form))))))

(defun org-mcp--call-tool (name args)
  "Call tool NAME with ARGS plist. Return result plist."
  (org-mcp-log name args)
  (pcase name
    ("org_get_entry"
     (org-mcp-query-get-entry (plist-get args :id)))
    ("org_query"
     (org-mcp-query-query
      (org-mcp--safe-read-query (plist-get args :query))
      (plist-get args :files)
      (plist-get args :columns)))
    ("org_get_children"
     (org-mcp-query-get-children (plist-get args :id) (plist-get args :columns)))
    ("org_get_properties"
     (org-mcp-query-get-properties (plist-get args :id) (plist-get args :inherited)))
    ("org_set_headline"
     (org-mcp-mutate-set-headline (plist-get args :id) (plist-get args :headline)))
    ("org_set_state"
     (org-mcp-mutate-set-state (plist-get args :id) (plist-get args :state)))
    ("org_set_property"
     (let ((result (org-mcp-mutate-set-property
                    (plist-get args :id) (plist-get args :key) (plist-get args :value))))
       (org-mcp-notify-emit-property-changed
        (plist-get args :id) (plist-get args :key) nil (plist-get args :value))
       result))
    ("org_append_body"
     (org-mcp-mutate-append-body (plist-get args :id) (plist-get args :text) (plist-get args :drawer)))
    ("org_capture"
     (let ((result (org-mcp-mutate-capture
                    :file (plist-get args :file)
                    :parent (plist-get args :parent)
                    :headline (plist-get args :headline)
                    :state (plist-get args :state)
                    :properties (plist-get args :properties)
                    :body (plist-get args :body)
                    :template-key (plist-get args :template_key))))
       (org-mcp-notify-emit-entry-created
        (plist-get result :id) (plist-get result :file)
        (plist-get args :headline) (plist-get args :state))
       result))
    ("org_get_config"
     (org-mcp-query-get-config (plist-get args :file)))
    ("org_list_files"
     (org-mcp-query-list-files))
    (_ (signal 'org-mcp-method-not-found (list name)))))

(define-error 'org-mcp-method-not-found "Method not found")

(defun org-mcp--dispatch (msg)
  "Dispatch a parsed JSON-RPC message MSG. Return response plist or nil."
  (let ((method (plist-get msg :method))
        (id (plist-get msg :id))
        (params (plist-get msg :params)))
    (pcase method
      ("initialize"
       (org-mcp--handle-initialize id params))
      ("notifications/initialized"
       nil)
      (_
       (if (not org-mcp--initialized)
           `(:jsonrpc "2.0" :id ,id
             :error (:code ,org-mcp-rpc-error-invalid-request
                     :message "Server not initialized"))
         (pcase method
           ("tools/list"
            (org-mcp--handle-tools-list id))
           ("tools/call"
            (org-mcp--handle-tools-call id params))
           (_
            `(:jsonrpc "2.0" :id ,id
              :error (:code ,org-mcp-rpc-error-method-not-found
                      :message ,(format "Unknown method: %s" method))))))))))

(defun org-mcp-start ()
  "Start the MCP server stdio loop.
Reads newline-delimited JSON-RPC from stdin, dispatches, and writes responses."
  (org-mcp-notify-enable)
  (setq org-mcp--initialized nil)
  (condition-case _err
      (while t
        (let ((line (condition-case nil
                        (read-string "")
                      (end-of-file (signal 'end-of-file nil)))))
          (when (and line (not (string-empty-p line)))
            (condition-case _parse-err
                (let* ((msg (org-mcp-rpc-parse line))
                       (response (org-mcp--dispatch msg)))
                  (when response
                    (org-mcp-rpc-send (json-serialize response))))
              (org-mcp-rpc-parse-error
               (org-mcp-rpc-send
                (org-mcp-rpc-format-error nil org-mcp-rpc-error-parse
                                          "Parse error" nil)))
              (org-mcp-rpc-invalid-request
               (org-mcp-rpc-send
                (org-mcp-rpc-format-error nil org-mcp-rpc-error-invalid-request
                                          "Invalid request" nil)))))))
    (end-of-file
     (org-mcp-notify-disable))))

(provide 'org-mcp)
;;; org-mcp.el ends here
