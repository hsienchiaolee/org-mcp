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
        (should (equal (plist-get result :heading) "Test task"))))))

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

(provide 'org-mcp-server-test)
;;; org-mcp-server-test.el ends here
