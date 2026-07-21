;;; org-latex-preview-codex.el --- LaTeX previews in Codex buffers -*- lexical-binding: t; -*-

;; Optional integration between `codex-app-server-mode' and
;; `org-latex-preview-plus'.

;;; Code:

(require 'cl-lib)
(require 'org-latex-preview-plus)

(defgroup org-latex-preview-codex nil
  "Preview LaTeX fragments in Codex app-server buffers."
  :group 'org-latex-preview-plus)

(defcustom org-latex-preview-codex-max-fragment-length 4000
  "Maximum length of a LaTeX fragment previewed in Codex buffers."
  :type 'integer
  :group 'org-latex-preview-codex)

(defcustom org-latex-preview-codex-ignore-code t
  "Non-nil means do not preview LaTeX fragments inside code faces."
  :type 'boolean
  :group 'org-latex-preview-codex)

(defcustom org-latex-preview-codex-preamble
  "\\documentclass{article}
\\usepackage[T1]{fontenc}
\\usepackage{amsmath}
\\usepackage{amssymb}
\\usepackage{amsfonts}
\\usepackage{xcolor}
"
  "LaTeX header used for previews in Codex buffers."
  :type 'string
  :group 'org-latex-preview-codex)

(defvar org-latex-preview-codex--enabled nil)

(defvar org-latex-preview-codex--code-faces
  '(codex-app-server-code-face
    font-lock-constant-face
    markdown-code-face
    markdown-inline-code-face
    markdown-pre-face))

(declare-function codex--app-server-output-point "codex-app-server")
(defvar codex-app-server-mode-map)

(defun org-latex-preview-codex--face-list (pos)
  "Return a flat list of faces at POS."
  (let ((face (get-text-property pos 'face)))
    (cond
     ((null face) nil)
     ((symbolp face) (list face))
     ((and (consp face) (keywordp (car face))) nil)
     ((consp face) (cl-remove-if-not #'symbolp (flatten-tree face)))
     (t nil))))

(defun org-latex-preview-codex--code-face-p (pos)
  "Return non-nil when POS appears to be inside rendered code."
  (and org-latex-preview-codex-ignore-code
       (cl-intersection
        (org-latex-preview-codex--face-list pos)
        org-latex-preview-codex--code-faces)))

(defun org-latex-preview-codex--escaped-p (pos)
  "Return non-nil when the character at POS is backslash-escaped."
  (let ((slashes 0)
        (cursor (1- pos)))
    (while (and (>= cursor (point-min))
                (eq (char-after cursor) ?\\))
      (cl-incf slashes)
      (cl-decf cursor))
    (cl-oddp slashes)))

(defun org-latex-preview-codex--search-closing (close limit &optional same-line)
  "Search for unescaped CLOSE before LIMIT.
When SAME-LINE is non-nil, do not search beyond the current line."
  (let ((search-limit (if same-line
                          (min limit (line-end-position))
                        limit))
        found)
    (while (and (not found) (search-forward close search-limit t))
      (unless (org-latex-preview-codex--escaped-p (match-beginning 0))
        (setq found (match-end 0))))
    found))

(defun org-latex-preview-codex--entry-at-match (limit)
  "Return a preview entry for the delimiter at match before LIMIT."
  (let* ((beg (match-beginning 0))
         (delimiter (match-string 0))
         (close nil)
         (same-line nil))
    (cond
     ((org-latex-preview-codex--code-face-p beg)
      nil)
     ((and (string= delimiter "$")
           (org-latex-preview-codex--escaped-p beg))
      nil)
     ((string= delimiter "$$")
      (setq close "$$"))
     ((string= delimiter "$")
      (setq close "$"
            same-line t))
     ((string= delimiter "\\(")
      (setq close "\\)"))
     ((string= delimiter "\\[")
      (setq close "\\]")))
    (when close
      (let ((end (save-excursion
                   (goto-char (match-end 0))
                   (org-latex-preview-codex--search-closing close limit same-line))))
        (when (and end
                   (> end beg)
                   (<= (- end beg)
                       org-latex-preview-codex-max-fragment-length)
                   (not (org-latex-preview-codex--code-face-p (1- end))))
          (list beg end (buffer-substring-no-properties beg end)))))))

(defun org-latex-preview-codex-collect-fragments (beg end)
  "Collect LaTeX preview entries between BEG and END."
  (let (entries)
    (save-excursion
      (goto-char beg)
      (while (re-search-forward "\\\\\\(?:[([]\\)\\|\\$\\$?" end t)
        (when-let* ((entry (org-latex-preview-codex--entry-at-match end)))
          (push entry entries)
          (goto-char (cadr entry)))))
    (nreverse entries)))

;;;###autoload
(defun org-latex-preview-codex-region (beg end)
  "Preview LaTeX fragments in Codex buffer region from BEG to END."
  (interactive "r")
  (when (display-graphic-p)
    (let ((entries (org-latex-preview-codex-collect-fragments beg end)))
      (org-latex-preview-clear-overlays beg end)
      (when entries
        (org-latex-preview-place
         org-latex-preview-process-default
         entries nil org-latex-preview-codex-preamble)))))

(defun org-latex-preview-codex--overlay-at-point ()
  "Return the LaTeX preview overlay at point, if any."
  (cl-find-if
   (lambda (ov)
     (eq (overlay-get ov 'org-overlay-type) 'org-latex-overlay))
   (overlays-at (point))))

(defun org-latex-preview-codex--show-source (ov)
  "Show the source text hidden by preview overlay OV."
  (overlay-put ov 'display nil)
  (overlay-put ov 'view-text t)
  (when-let* ((face (overlay-get ov 'face)))
    (overlay-put ov 'hidden-face face)
    (overlay-put ov 'face nil)))

(defun org-latex-preview-codex--show-preview (ov)
  "Show the preview image for preview overlay OV."
  (overlay-put ov 'view-text nil)
  (when-let* ((face (overlay-get ov 'hidden-face)))
    (overlay-put ov 'face face)
    (overlay-put ov 'hidden-face nil))
  (overlay-put ov 'display (overlay-get ov 'preview-image)))

;;;###autoload
(defun org-latex-preview-codex-toggle-at-point ()
  "Toggle the Codex LaTeX preview overlay at point.
When the preview image is visible, reveal the source text.  When
the source text is visible, restore the preview image."
  (interactive)
  (if-let* ((ov (org-latex-preview-codex--overlay-at-point)))
      (if (overlay-get ov 'display)
          (progn
            (org-latex-preview-codex--show-source ov)
            (message "LaTeX preview source shown"))
        (org-latex-preview-codex--show-preview ov)
        (message "LaTeX preview restored"))
    (message "No LaTeX preview at point")))

(defun org-latex-preview-codex--after-completed-message (item)
  "Preview LaTeX in a completed Codex agent message ITEM."
  (when-let* ((table (and (boundp 'codex--app-server-agent-items)
                         codex--app-server-agent-items))
              (start (gethash (alist-get 'id item) table))
              ((markerp start)))
    (org-latex-preview-codex-region
     (marker-position start) (codex--app-server-output-point))))

(defun org-latex-preview-codex--around-render-history-agent (orig item)
  "Run ORIG for historical agent ITEM, then preview LaTeX in its output."
  (let ((start (codex--app-server-output-point)))
    (prog1 (funcall orig item)
      (org-latex-preview-codex-region
       start (codex--app-server-output-point)))))

(defun org-latex-preview-codex--around-render-transcript-agent (orig text)
  "Run ORIG for transcript agent TEXT, then preview LaTeX in its output."
  (let ((start (codex--app-server-output-point)))
    (prog1 (funcall orig text)
      (org-latex-preview-codex-region
       start (codex--app-server-output-point)))))

;;;###autoload
(defun org-latex-preview-codex-enable ()
  "Enable automatic LaTeX previews in Codex app-server buffers."
  (interactive)
  (unless org-latex-preview-codex--enabled
    (with-eval-after-load 'codex-app-server
      (advice-add 'codex--app-server-fontify-completed-message
                  :after #'org-latex-preview-codex--after-completed-message)
      (advice-add 'codex--app-server-render-history-agent
                  :around #'org-latex-preview-codex--around-render-history-agent)
      (advice-add 'codex--app-server-render-transcript-agent
                  :around #'org-latex-preview-codex--around-render-transcript-agent)
      (define-key codex-app-server-mode-map
                  (kbd "C-c C-x C-l")
                  #'org-latex-preview-codex-toggle-at-point))
    (setq org-latex-preview-codex--enabled t)))

;;;###autoload
(defun org-latex-preview-codex-disable ()
  "Disable automatic LaTeX previews in Codex app-server buffers."
  (interactive)
  (when org-latex-preview-codex--enabled
    (with-eval-after-load 'codex-app-server
      (advice-remove 'codex--app-server-fontify-completed-message
                     #'org-latex-preview-codex--after-completed-message)
      (advice-remove 'codex--app-server-render-history-agent
                     #'org-latex-preview-codex--around-render-history-agent)
      (advice-remove 'codex--app-server-render-transcript-agent
                     #'org-latex-preview-codex--around-render-transcript-agent)
      (define-key codex-app-server-mode-map
                  (kbd "C-c C-x C-l")
                  nil))
    (setq org-latex-preview-codex--enabled nil)))

(provide 'org-latex-preview-codex)

;;; org-latex-preview-codex.el ends here
