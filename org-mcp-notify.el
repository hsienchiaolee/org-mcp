;;; org-mcp-notify.el --- Notification layer for org-mcp -*- lexical-binding: t; -*-

;; URL: https://github.com/hsienchiaolee/org-mcp

;;; Commentary:

;; Bridges Org hooks to MCP notifications. Emits JSON-RPC notifications
;; to stdout when Org state changes occur.

;;; Code:

(require 'org)
(require 'org-id)
(require 'org-mcp-rpc)

(defvar org-last-state)
(defvar org-state)

(defvar org-mcp-notify--enabled nil
  "Non-nil when notification hooks are active.")

(defun org-mcp-notify--on-state-change ()
  "Hook function for `org-after-todo-state-change-hook'.
Emits an entry_state_changed notification."
  (when org-mcp-notify--enabled
    (let ((id (org-id-get))
          (file (buffer-file-name))
          (headline (substring-no-properties (org-get-heading t t t t))))
      (when id
        (org-mcp-rpc-send
         (org-mcp-rpc-format-notification
          "entry_state_changed"
          (list :id id
                :file file
                :headline headline
                :old_state org-last-state
                :new_state org-state)))))))

(defun org-mcp-notify-emit-property-changed (id key old-value new-value)
  "Emit a property_changed notification."
  (when org-mcp-notify--enabled
    (org-mcp-rpc-send
     (org-mcp-rpc-format-notification
      "property_changed"
      (list :id id :key key :old_value old-value :new_value new-value)))))

(defun org-mcp-notify-emit-entry-created (id file headline state)
  "Emit an entry_created notification."
  (when org-mcp-notify--enabled
    (org-mcp-rpc-send
     (org-mcp-rpc-format-notification
      "entry_created"
      (list :id id :file file :headline headline :state state)))))

(defun org-mcp-notify-enable ()
  "Register Org hooks for MCP notifications."
  (setq org-mcp-notify--enabled t)
  (add-hook 'org-after-todo-state-change-hook #'org-mcp-notify--on-state-change))

(defun org-mcp-notify-disable ()
  "Unregister Org hooks for MCP notifications."
  (setq org-mcp-notify--enabled nil)
  (remove-hook 'org-after-todo-state-change-hook #'org-mcp-notify--on-state-change))

(provide 'org-mcp-notify)
;;; org-mcp-notify.el ends here
