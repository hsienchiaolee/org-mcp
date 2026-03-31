;;; org-mcp-server-test.el --- Tests for server dispatch -*- lexical-binding: t; -*-

(require 'test-helper)
(require 'org-mcp)

(ert-deftest org-mcp-dispatch-initialize ()
  "Initialize handshake returns capabilities."
  (let* ((request '(:jsonrpc "2.0" :id 1 :method "initialize"
                    :params (:protocolVersion "2025-03-26"
                             :capabilities (:__placeholder t)
                             :clientInfo (:name "test" :version "1.0"))))
         (response (org-mcp--dispatch request)))
    (should (plist-get response :result))
    (let ((result (plist-get response :result)))
      (should (equal (plist-get result :protocolVersion) "2025-03-26"))
      (should (equal (plist-get (plist-get result :serverInfo) :name) "org-mcp")))))

(ert-deftest org-mcp-dispatch-before-init ()
  "Requests before initialization are rejected."
  (let ((org-mcp--initialized nil))
    (let* ((request '(:jsonrpc "2.0" :id 1 :method "tools/call"
                      :params (:name "org_get_entry" :arguments (:id "x"))))
           (response (org-mcp--dispatch request)))
      (should (plist-get response :error)))))

(ert-deftest org-mcp-dispatch-tools-call ()
  "Dispatch a tools/call request to the right handler."
  (let ((org-mcp--initialized t))
    (org-mcp-test-with-temp-org
        "* TODO Test task
:PROPERTIES:
:ID: dispatch-1
:END:
"
      (let* ((request '(:jsonrpc "2.0" :id 2 :method "tools/call"
                        :params (:name "org_get_entry" :arguments (:id "dispatch-1"))))
             (response (org-mcp--dispatch request))
             (result (plist-get response :result)))
        (should result)
        (should (equal (plist-get result :id) "dispatch-1"))
        (should (equal (plist-get result :headline) "Test task"))))))

(ert-deftest org-mcp-dispatch-method-not-found ()
  "Unknown tool returns method-not-found error."
  (let ((org-mcp--initialized t))
    (let* ((request '(:jsonrpc "2.0" :id 3 :method "tools/call"
                      :params (:name "nonexistent" :arguments (:__placeholder t))))
           (response (org-mcp--dispatch request)))
      (should (plist-get response :error))
      (should (= (plist-get (plist-get response :error) :code) -32601)))))

(ert-deftest org-mcp-dispatch-tools-list ()
  "tools/list returns all available tools with schemas."
  (let ((org-mcp--initialized t))
    (let* ((request '(:jsonrpc "2.0" :id 4 :method "tools/list"))
           (response (org-mcp--dispatch request))
           (tools (plist-get (plist-get response :result) :tools)))
      (should (>= (length tools) 8))
      ;; Each tool should have name, description, inputSchema
      (dolist (tool tools)
        (should (plist-get tool :name))
        (should (plist-get tool :description))
        (should (plist-get tool :inputSchema))))))

(ert-deftest org-mcp-dispatch-serializes-valid-jsonrpc ()
  "Dispatch returns plists that serialize to valid JSON-RPC 2.0."
  (let ((org-mcp--initialized t))
    (org-mcp-test-with-temp-org
        "* TODO Task
:PROPERTIES:
:ID: serial-1
:END:
"
      ;; Success response
      (let* ((response (org-mcp--dispatch
                        '(:jsonrpc "2.0" :id 1 :method "tools/call"
                          :params (:name "org_get_entry" :arguments (:id "serial-1")))))
             (json-str (json-serialize response))
             (parsed (org-mcp-test-parse-json json-str)))
        (should (equal (plist-get parsed :jsonrpc) "2.0"))
        (should (equal (plist-get parsed :id) 1))
        (should (plist-get parsed :result)))
      ;; Error response
      (let* ((response (org-mcp--dispatch
                        '(:jsonrpc "2.0" :id 2 :method "tools/call"
                          :params (:name "org_get_entry" :arguments (:id "missing")))))
             (json-str (json-serialize response))
             (parsed (org-mcp-test-parse-json json-str)))
        (should (equal (plist-get parsed :jsonrpc) "2.0"))
        (should (equal (plist-get parsed :id) 2))
        (should (plist-get parsed :error))
        (should (numberp (plist-get (plist-get parsed :error) :code)))))))

(ert-deftest org-mcp-dispatch-capture-missing-headline-returns-invalid-params ()
  "Capture without headline returns -32602, not -32603."
  (let ((org-mcp--initialized t))
    (org-mcp-test-with-temp-org "* Test\n"
      (let* ((response (org-mcp--handle-tools-call
                        1 `(:name "org_capture"
                            :arguments (:file ,temp-file :headline nil))))
             (err (plist-get response :error)))
        (should (= (plist-get err :code) -32602))))))

(ert-deftest org-mcp-dispatch-internal-error-hides-details ()
  "Internal errors return generic message, not raw Emacs error strings."
  (let ((org-mcp--initialized t))
    (cl-letf (((symbol-function 'org-mcp-query-get-entry)
               (lambda (_id) (error "File not found: /secret/path/file.org"))))
      (let* ((response (org-mcp--handle-tools-call
                        1 '(:name "org_get_entry" :arguments (:id "x"))))
             (err (plist-get response :error)))
        (should (= (plist-get err :code) -32603))
        (should (equal (plist-get err :message) "Internal error"))
        (should-not (string-match-p "secret" (plist-get err :message)))))))

(ert-deftest org-mcp-safe-read-query-rejects-reader-macro ()
  "Query with #. reader macro is rejected as invalid input."
  (let ((org-mcp--initialized t))
    (org-mcp-test-with-temp-org "* TODO Task\n"
      (let* ((response (org-mcp--handle-tools-call
                        1 '(:name "org_query"
                            :arguments (:query "#.(error \"pwned\")")))))
        (should (plist-get response :error))
        (should (= (plist-get (plist-get response :error) :code) -32602))))))

(ert-deftest org-mcp-safe-read-query-rejects-vector ()
  "Query containing vector syntax is rejected."
  (let ((org-mcp--initialized t))
    (org-mcp-test-with-temp-org "* TODO Task\n"
      (let* ((response (org-mcp--handle-tools-call
                        1 '(:name "org_query"
                            :arguments (:query "[1 2 3]")))))
        (should (plist-get response :error))
        (should (= (plist-get (plist-get response :error) :code) -32602))))))

(provide 'org-mcp-server-test)
;;; org-mcp-server-test.el ends here
