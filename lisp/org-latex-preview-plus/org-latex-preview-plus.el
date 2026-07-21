;;; org-latex-preview-plus.el --- Overlay Org LaTeX previews -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Load Tec/Karthink's newer Org LaTeX preview implementation on top of
;; a stock Org install.

;;; Code:

(require 'org)
(require 'org-latex-preview-plus-compat)

(defgroup org-latex-preview-plus nil
  "Compatibility layer for the newer Org LaTeX preview implementation."
  :group 'org)

(defcustom org-latex-preview-plus-translate-legacy-options t
  "Non-nil means translate `org-format-latex-options' on load."
  :type 'boolean
  :group 'org-latex-preview-plus)

(require 'org-latex-preview)

(defun org-latex-preview-plus--translate-legacy-options ()
  "Carry useful values from classic Org preview options to the new preview."
  (when (and org-latex-preview-plus-translate-legacy-options
             (boundp 'org-format-latex-options)
             (boundp 'org-latex-preview-appearance-options))
    (let ((legacy org-format-latex-options))
      (setq org-latex-preview-appearance-options
            (org-combine-plists
             org-latex-preview-appearance-options
             (list
              :foreground (plist-get legacy :foreground)
              :background (plist-get legacy :background)
              :scale (or (plist-get legacy :scale)
                         (plist-get org-latex-preview-appearance-options :scale))
              :matchers (or (plist-get legacy :matchers)
                            (plist-get org-latex-preview-appearance-options
                                       :matchers))))))))

(org-latex-preview-plus--translate-legacy-options)

(when (and (boundp 'org-preview-latex-default-process)
           (boundp 'org-latex-preview-process-default)
           org-preview-latex-default-process)
  (setq org-latex-preview-process-default org-preview-latex-default-process))

(defalias 'org-clear-latex-preview #'org-latex-preview-clear-overlays)

(provide 'org-latex-preview-plus)

;;; org-latex-preview-plus.el ends here
