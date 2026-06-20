;; -*- lexical-binding: t; -*-
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(require 'use-package)

(org-babel-load-file
 (expand-file-name
  "config.org"
  user-emacs-directory))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ignored-local-variable-values '((eval when (fboundp 'rainbow-mode) (rainbow-mode 1))))
 '(org-format-latex-options
   '(:foreground default :background default :scale 2.0 :html-foreground
		 "Black" :html-background "Transparent" :html-scale
		 1.0 :matchers ("begin" "$1" "$" "$$" "\\(" "\\[")))
 '(package-selected-packages
   '(apheleia avy code-cells comint-mime company corfu denote gptel-quick
	      gruvbox-theme jinx jupyter kdl-mode lsp-bridge lsp-mode
	      magit marginalia multi-vterm multiple-cursors
	      org-journal org-modern org-modern-indent org-roam popper
	      ruff-format toc-org uniline uv-mode vertico
	      visual-fill-column xdg-launcher yasnippet
	      yasnippet-snippets))
 '(package-vc-selected-packages
   '((gptel-quick :url "https://github.com/karthink/gptel-quick")
     (xdg-launcher :url "https://github.com/emacs-exwm/xdg-launcher"))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
