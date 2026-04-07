;;; org-mcp-access-test.el --- Tests for access control -*- lexical-binding: t; -*-

(require 'test-helper)
(require 'org-mcp-access)
(require 'org-mcp-query)
(require 'org-mcp-mutate)

;;; org-mcp-check-access

(ert-deftest org-mcp-access-allowed ()
  "File under an allowed directory passes access check."
  (let* ((dir (make-temp-file "org-mcp-sec-allowed-" t))
         (file (expand-file-name "test.org" dir))
         (org-mcp-allowed-directories (list dir)))
    (unwind-protect
        (progn
          (write-region "" nil file)
          (should (org-mcp-check-access file)))
      (delete-file file)
      (delete-directory dir))))

(ert-deftest org-mcp-access-denied ()
  "File outside allowed directories signals org-mcp-access-denied."
  (let* ((allowed-dir (make-temp-file "org-mcp-sec-allowed-" t))
         (other-dir (make-temp-file "org-mcp-sec-other-" t))
         (file (expand-file-name "test.org" other-dir))
         (org-mcp-allowed-directories (list allowed-dir)))
    (unwind-protect
        (progn
          (write-region "" nil file)
          (should-error (org-mcp-check-access file)
                        :type 'org-mcp-access-denied))
      (delete-file file)
      (delete-directory other-dir)
      (delete-directory allowed-dir))))

(ert-deftest org-mcp-access-default-uses-agenda-dirs ()
  "When org-mcp-allowed-directories is nil, agenda file dirs are used."
  (org-mcp-test-with-temp-org "* Test\n"
    (let ((org-mcp-allowed-directories nil))
      (should (org-mcp-check-access (car org-agenda-files))))))

(ert-deftest org-mcp-access-default-denies-other ()
  "When org-mcp-allowed-directories is nil, files outside agenda dirs are denied."
  (org-mcp-test-with-temp-org "* Test\n"
    (let* ((org-mcp-allowed-directories nil)
           (other-dir (make-temp-file "org-mcp-sec-other-" t))
           (other-file (expand-file-name "other.org" other-dir)))
      (unwind-protect
          (progn
            (write-region "" nil other-file)
            (should-error (org-mcp-check-access other-file)
                          :type 'org-mcp-access-denied))
        (delete-file other-file)
        (delete-directory other-dir)))))

;;; Integration: find-entry checks access

(ert-deftest org-mcp-access-find-entry-denied ()
  "org-mcp-query--find-entry signals access-denied for files outside allowed dirs."
  (org-mcp-test-with-temp-org
      "* Task
:PROPERTIES:
:ID: acc-find-1
:END:
"
    (let* ((other-dir (make-temp-file "org-mcp-sec-other-" t))
           (org-mcp-allowed-directories (list other-dir)))
      (unwind-protect
          (should-error (org-mcp-query--find-entry "acc-find-1")
                        :type 'org-mcp-access-denied)
        (delete-directory other-dir)))))

(ert-deftest org-mcp-access-find-entry-allowed ()
  "org-mcp-query--find-entry succeeds for files in allowed dirs."
  (org-mcp-test-with-temp-org
      "* Task
:PROPERTIES:
:ID: acc-find-2
:END:
"
    (let* ((agenda-dir (file-name-directory (car org-agenda-files)))
           (org-mcp-allowed-directories (list agenda-dir)))
      (should (org-mcp-query--find-entry "acc-find-2")))))

;;; Integration: query filters disallowed files

(ert-deftest org-mcp-access-query-skips-disallowed ()
  "org-mcp-query-query returns no results from files outside allowed dirs."
  (org-mcp-test-with-temp-org
      "* TODO Task
:PROPERTIES:
:ID: acc-query-1
:END:
"
    (let* ((other-dir (make-temp-file "org-mcp-sec-other-" t))
           (org-mcp-allowed-directories (list other-dir)))
      (unwind-protect
          (should (= 0 (plist-get (org-mcp-query-query '(todo "TODO")) :count)))
        (delete-directory other-dir)))))

;;; Integration: capture checks file access

(ert-deftest org-mcp-access-append-body-denied ()
  "org-mcp-mutate-append-body signals access-denied for files outside allowed dirs."
  (org-mcp-test-with-temp-org
      "* Task
:PROPERTIES:
:ID: acc-body-1
:END:
"
    (let* ((other-dir (make-temp-file "org-mcp-sec-other-" t))
           (org-mcp-allowed-directories (list other-dir)))
      (unwind-protect
          (should-error (org-mcp-mutate-append-body "acc-body-1" "text")
                        :type 'org-mcp-access-denied)
        (delete-directory other-dir)))))

(ert-deftest org-mcp-access-get-config-denied ()
  "org-mcp-query-get-config signals access-denied for files outside allowed dirs."
  (org-mcp-test-with-temp-org "* Test\n"
    (let* ((other-dir (make-temp-file "org-mcp-sec-other-" t))
           (other-file (expand-file-name "other.org" other-dir))
           (org-mcp-allowed-directories (list (file-name-directory (car org-agenda-files)))))
      (unwind-protect
          (progn
            (write-region "* Task\n" nil other-file)
            (should-error (org-mcp-query-get-config other-file)
                          :type 'org-mcp-access-denied))
        (when (get-file-buffer other-file)
          (kill-buffer (get-file-buffer other-file)))
        (delete-file other-file)
        (delete-directory other-dir)))))

(ert-deftest org-mcp-access-capture-file-denied ()
  "org-mcp-mutate-capture signals access-denied when target file is disallowed."
  (org-mcp-test-with-temp-org "* Existing\n"
    (let* ((other-dir (make-temp-file "org-mcp-sec-other-" t))
           (org-mcp-allowed-directories (list other-dir)))
      (unwind-protect
          (should-error (org-mcp-mutate-capture
                         :file (car org-agenda-files)
                         :headline "New entry")
                        :type 'org-mcp-access-denied)
        (delete-directory other-dir)))))

(ert-deftest org-mcp-access-list-files-filters ()
  "org-mcp-query-list-files only returns files in allowed directories."
  (org-mcp-test-with-temp-org "* Test\n"
    (let* ((other-dir (make-temp-file "org-mcp-sec-other-" t))
           (other-file (expand-file-name "other.org" other-dir))
           (org-mcp-allowed-directories (list other-dir)))
      (unwind-protect
          (progn
            (write-region "* Other\n" nil other-file)
            (let ((org-agenda-files (list (car org-agenda-files) other-file)))
              (let* ((result (org-mcp-query-list-files))
                     (files (append (plist-get result :files) nil)))
                ;; Only the file in other-dir (allowed) should appear
                (should (= (length files) 1))
                (should (string-match-p "other\\.org" (car files))))))
        (when (get-file-buffer other-file)
          (kill-buffer (get-file-buffer other-file)))
        (delete-file other-file)
        (delete-directory other-dir)))))

;;; URI parsing

(ert-deftest org-mcp-access-parse-file-uri-basic ()
  "Parses a standard file:// URI to a local path."
  (should (equal (org-mcp-access--parse-file-uri "file:///home/user/project")
                 "/home/user/project")))

(ert-deftest org-mcp-access-parse-file-uri-percent-encoding ()
  "Decodes percent-encoded characters in file URIs."
  (should (equal (org-mcp-access--parse-file-uri "file:///path/to/my%20project")
                 "/path/to/my project")))

(ert-deftest org-mcp-access-parse-file-uri-non-file ()
  "Returns nil for non-file:// URIs."
  (should (null (org-mcp-access--parse-file-uri "https://example.com")))
  (should (null (org-mcp-access--parse-file-uri "ssh://host/path"))))

(ert-deftest org-mcp-access-parse-file-uri-empty ()
  "Returns nil for nil or empty input."
  (should (null (org-mcp-access--parse-file-uri nil)))
  (should (null (org-mcp-access--parse-file-uri ""))))

(provide 'org-mcp-access-test)
;;; org-mcp-access-test.el ends here
