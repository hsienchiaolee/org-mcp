;;; org-mcp-integration-test.el --- End-to-end tests -*- lexical-binding: t; -*-

(require 'test-helper)
(require 'org-mcp)

(ert-deftest org-mcp-integration-full-workflow ()
  "Full workflow: init, query, mutate, verify."
  (org-mcp-test-with-clean-session
  (let ((sent-messages nil))
    (cl-letf (((symbol-function 'org-mcp-rpc-send)
               (lambda (msg) (push msg sent-messages))))
      (org-mcp-test-with-temp-org
          "* TODO Build API
:PROPERTIES:
:ID: integ-1
:EFFORT: 3h
:END:
** TODO Write tests
:PROPERTIES:
:ID: integ-2
:END:
** TODO Write code
:PROPERTIES:
:ID: integ-3
:END:
"
        ;; Initialize
        (let ((init-resp (org-mcp--dispatch
                          '(:jsonrpc "2.0" :id 1 :method "initialize"
                            :params (:protocolVersion "2025-03-26"
                                     :capabilities (:__placeholder t)
                                     :clientInfo (:name "test" :version "1.0"))))))
          (should (plist-get init-resp :result)))

        ;; Get entry
        (let* ((resp (org-mcp--dispatch
                      '(:jsonrpc "2.0" :id 2 :method "tools/call"
                        :params (:name "org_get_entry" :arguments (:id "integ-1")))))
               (result (plist-get resp :result)))
          (should (equal (plist-get result :headline) "Build API")))

        ;; Get children
        (let* ((resp (org-mcp--dispatch
                      '(:jsonrpc "2.0" :id 3 :method "tools/call"
                        :params (:name "org_get_children" :arguments (:id "integ-1")))))
               (children (plist-get (plist-get resp :result) :children)))
          (should (= (length children) 2)))

        ;; Set state
        (org-mcp-notify-enable)
        (let* ((resp (org-mcp--dispatch
                      '(:jsonrpc "2.0" :id 4 :method "tools/call"
                        :params (:name "org_set_state"
                                 :arguments (:id "integ-2" :state "DONE")))))
               (result (plist-get resp :result)))
          (should (equal (plist-get result :new_state) "DONE")))
        (org-mcp-notify-disable)

        ;; Verify state changed
        (let* ((resp (org-mcp--dispatch
                      '(:jsonrpc "2.0" :id 5 :method "tools/call"
                        :params (:name "org_get_entry" :arguments (:id "integ-2")))))
               (result (plist-get resp :result)))
          (should (equal (plist-get result :state) "DONE"))))))))

(ert-deftest org-mcp-integration-error-handling ()
  "Errors are properly formatted as JSON-RPC errors."
  (let ((org-mcp--initialized t))
    ;; Missing entry
    (let* ((resp (org-mcp--dispatch
                  '(:jsonrpc "2.0" :id 1 :method "tools/call"
                    :params (:name "org_get_entry" :arguments (:id "nonexistent")))))
           (err (plist-get resp :error)))
      (should (= (plist-get err :code) -32602))
      (should (string-match-p "not found" (plist-get err :message))))

    ;; Unknown tool
    (let* ((resp (org-mcp--dispatch
                  '(:jsonrpc "2.0" :id 2 :method "tools/call"
                    :params (:name "unknown_tool" :arguments (:__placeholder t)))))
           (err (plist-get resp :error)))
      (should err))))

(provide 'org-mcp-integration-test)
;;; org-mcp-integration-test.el ends here
