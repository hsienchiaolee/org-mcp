;;; org-mcp-rpc-test.el --- Tests for JSON-RPC layer -*- lexical-binding: t; -*-

(require 'test-helper)
(require 'org-mcp-rpc)

(ert-deftest org-mcp-rpc-parse-valid-request ()
  "Parse a valid JSON-RPC 2.0 request."
  (let ((msg (org-mcp-rpc-parse "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"org_get_entry\",\"params\":{\"id\":\"abc\"}}")))
    (should (equal (plist-get msg :jsonrpc) "2.0"))
    (should (equal (plist-get msg :id) 1))
    (should (equal (plist-get msg :method) "org_get_entry"))
    (should (equal (plist-get (plist-get msg :params) :id) "abc"))))

(ert-deftest org-mcp-rpc-parse-notification ()
  "Parse a notification (no id)."
  (let ((msg (org-mcp-rpc-parse "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")))
    (should (equal (plist-get msg :method) "notifications/initialized"))
    (should (null (plist-get msg :id)))))

(ert-deftest org-mcp-rpc-parse-malformed-json ()
  "Malformed JSON signals an error."
  (should-error (org-mcp-rpc-parse "not json{") :type 'org-mcp-rpc-parse-error))

(ert-deftest org-mcp-rpc-parse-missing-jsonrpc ()
  "Missing jsonrpc field signals invalid-request."
  (should-error (org-mcp-rpc-parse "{\"id\":1,\"method\":\"foo\"}") :type 'org-mcp-rpc-invalid-request))

(ert-deftest org-mcp-rpc-format-result ()
  "Format a success response."
  (let* ((json-str (org-mcp-rpc-format-result 1 '(:count 2)))
         (parsed (org-mcp-test-parse-json json-str)))
    (should (equal (plist-get parsed :jsonrpc) "2.0"))
    (should (equal (plist-get parsed :id) 1))
    (should (equal (plist-get (plist-get parsed :result) :count) 2))))

(ert-deftest org-mcp-rpc-format-error ()
  "Format an error response."
  (let* ((json-str (org-mcp-rpc-format-error 1 -32602 "Entry not found" '(:id "missing")))
         (parsed (org-mcp-test-parse-json json-str)))
    (should (equal (plist-get parsed :id) 1))
    (should (equal (plist-get (plist-get parsed :error) :code) -32602))
    (should (equal (plist-get (plist-get parsed :error) :message) "Entry not found"))))

(ert-deftest org-mcp-rpc-format-notification ()
  "Format a server notification."
  (let* ((json-str (org-mcp-rpc-format-notification "entry_state_changed" '(:id "abc")))
         (parsed (org-mcp-test-parse-json json-str)))
    (should (equal (plist-get parsed :method) "entry_state_changed"))
    (should (null (plist-get parsed :id)))))

(provide 'org-mcp-rpc-test)
;;; org-mcp-rpc-test.el ends here
