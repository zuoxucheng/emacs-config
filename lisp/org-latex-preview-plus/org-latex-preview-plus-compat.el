;;; org-latex-preview-plus-compat.el --- Org preview compatibility -*- lexical-binding: t; -*-

;; This file vendors small helper APIs from Tec/Karthink's Org preview
;; branch when they are not present in the running Org.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-macs)
(require 'org-persist)
(require 'ox-latex)

(declare-function org-async-call "org-latex-preview-plus-compat")
(declare-function org-async--sentinel "org-latex-preview-plus-compat")
(declare-function org-async--filter "org-latex-preview-plus-compat")
(declare-function org-async--monitor "org-latex-preview-plus-compat")
(declare-function org-async--cleanup-process "org-latex-preview-plus-compat")
(declare-function org-async--execute-callback "org-latex-preview-plus-compat")
(declare-function org-latex--precompile-preamble "org-latex-preview-plus-compat")

(defvar org-async-process-limit 4
  "Maximum number of preview helper processes to run at once.")

(defvar org-async-timeout 120
  "Default timeout for a process started via `org-async-call'.")

(defvar org-async-check-timeout-interval 1
  "Check for overdue async processes every this many seconds.")

(defvar org-async--stack nil
  "List of currently running async task forms.")

(defvar org-async--wait-queue nil
  "List of queued async task forms.")

(defvar org-async--counter 0)

(unless (fboundp 'org-async-call)
  (cl-defun org-async-call
      (proc &key success failure filter buffer info timeout now
            process-variables (dir default-directory) (coding 'utf-8))
    "Start PROC and register it with callbacks SUCCESS and FAILURE."
    (cond
     ((and (consp proc) (eq (car proc) 'org-async-task))
      (apply #'org-async-call (cdr proc)))
     ((or now (< (length org-async--stack) org-async-process-limit))
      (let ((proc
             (let ((default-directory (or dir default-directory))
                   (process-adaptive-read-buffering
                    (cadr (assoc 'process-adaptive-read-buffering
                                 process-variables)))
                   (process-connection-type
                    (cadr (assoc 'process-connection-type process-variables)))
                   (read-process-output-max
                    (or (cadr (assq 'read-process-output-max process-variables))
                        read-process-output-max)))
               (cond
                ((processp proc) proc)
                ((stringp proc)
                 (start-process-shell-command
                  (format "org-async-%d" (cl-incf org-async--counter))
                  buffer proc))
                ((consp proc)
                 (apply #'start-process
                        (format "org-async-%s-%d"
                                (car proc) (cl-incf org-async--counter))
                        buffer proc))
                (t
                 (error "Async process input %S is not a recognized format"
                        proc)))))
            (timeout (or timeout org-async-timeout)))
        (set-process-sentinel proc #'org-async--sentinel)
        (when filter (set-process-filter proc #'org-async--filter))
        (when coding (set-process-coding-system proc coding coding))
        (push (list proc
                    :success success
                    :failure failure
                    :filter filter
                    :buffer (if (eq buffer t)
                                (cons :temp (generate-new-buffer " *temp*" t))
                              buffer)
                    :info info
                    :timeout timeout
                    :start-time (float-time))
              org-async--stack)
        (org-async--monitor t)
        (car org-async--stack)))
     (t
      (setq org-async--wait-queue
            (append org-async--wait-queue
                    (list (list proc
                                :success success
                                :failure failure
                                :filter filter
                                :buffer buffer
                                :info info
                                :dir dir
                                :timeout timeout
                                :coding coding))))
      (last org-async--wait-queue)))))

(defvar org-async--blocking-tasks nil
  "List of async tasks currently being waited on.")

(unless (fboundp 'org-async-wait-for)
  (defun org-async-wait-for (&rest tasks)
    "Block until every task of TASKS has finished."
    (setq org-async--blocking-tasks tasks)
    (while org-async--blocking-tasks
      (dolist (task org-async--blocking-tasks)
        (accept-process-output (car task))))))

(unless (fboundp 'org-async--filter)
  (defun org-async--filter (process string)
    "After PROCESS receives STRING, call the async filter."
    (when-let* ((proc-info (alist-get process org-async--stack)))
      (let ((filter (plist-get proc-info :filter))
            (buffer (plist-get proc-info :buffer)))
        (if buffer
            (with-current-buffer buffer
              (save-excursion
                (goto-char (point-max))
                (insert string))
              (funcall filter process string (plist-get proc-info :info)))
          (funcall filter process string (plist-get proc-info :info)))))))

(unless (fboundp 'org-async--sentinel)
  (defun org-async--sentinel (process _signal)
    "Watch PROCESS for death and run the relevant callback."
    (pcase (process-status process)
      ((and 'exit (guard (= 0 (process-exit-status process))))
       (org-async--cleanup-process process))
      ((or 'exit 'signal 'failed)
       (org-async--cleanup-process process 'failed)))))

(unless (fboundp 'org-async--cleanup-process)
  (defun org-async--cleanup-process (process &optional failed)
    "Remove PROCESS from the async stack, and run its callback."
    (when (assq process org-async--stack)
      (let* ((proc-info (cdr (assq process org-async--stack)))
             (buffer-val (plist-get proc-info :buffer))
             (proc-buf (if (consp buffer-val) (cdr buffer-val) buffer-val))
             (blocking-p (cl-member process org-async--blocking-tasks
                                    :key #'car)))
        (setq org-async--stack
              (delq (assq process org-async--stack) org-async--stack))
        (while (accept-process-output process))
        (org-async--execute-callback
         (plist-get proc-info
                    (if (and (not failed)
                             (= 0 (process-exit-status process)))
                        :success :failure))
         (process-exit-status process)
         proc-buf
         (plist-get proc-info :info)
         blocking-p)
        (when blocking-p
          (setq org-async--blocking-tasks
                (cl-delete process org-async--blocking-tasks :key #'car)))
        (when (and (consp buffer-val) (eq :temp (car buffer-val)))
          (kill-buffer proc-buf)))
      (when (and org-async--wait-queue
                 (< (length org-async--stack) org-async-process-limit))
        (apply #'org-async-call (pop org-async--wait-queue))))))

(unless (fboundp 'org-async--execute-callback)
  (defun org-async--execute-callback
      (callback exit-code process-buffer info &optional blocking)
    "Run CALLBACK with EXIT-CODE, PROCESS-BUFFER, and INFO."
    (cond
     ((stringp callback)
      (message callback exit-code process-buffer info))
     ((functionp callback)
      (funcall callback exit-code process-buffer info))
     ((consp callback)
      (if (eq (car callback) 'org-async-task)
          (if blocking
              (push (org-async-call callback) org-async--blocking-tasks)
            (org-async-call callback))
        (dolist (clbk callback)
          (org-async--execute-callback
           clbk exit-code process-buffer info blocking))))
     ((null callback))
     (t
      (message "Ignoring invalid `org-async-call' callback: %S" callback)))))

(defvar org-async--monitor-scheduled nil)

(unless (fboundp 'org-async--monitor)
  (defun org-async--monitor (&optional force)
    "Check each process against its timeout."
    (when (or force (null org-async--monitor-scheduled))
      (dolist (stack-proc org-async--stack)
        (if (process-live-p (car stack-proc))
            (let ((timeout (plist-get (cdr stack-proc) :timeout)))
              (when (and (numberp timeout)
                         (< 0 timeout
                            (- (float-time)
                               (plist-get (cdr stack-proc) :start-time))))
                (kill-process (car stack-proc))))
          (org-async--cleanup-process (car stack-proc))))
      (if org-async--stack
          (setq org-async--monitor-scheduled
                (run-at-time org-async-check-timeout-interval
                             nil #'org-async--monitor t))
        (setq org-async--monitor-scheduled nil)))))

(defvar org-latex-precompile t
  "Precompile the LaTeX preamble during preview generation.")

(defconst org-latex--precompile-log "*Org LaTeX Precompilation*")

(defvar org-latex-precompile-command
  "%l -output-directory %o -ini -jobname=%b \"&%L\" mylatexformat.ltx %f")

(unless (fboundp 'org-latex--precompile)
  (defun org-latex--precompile (info preamble &optional tempfile-p)
    "Precompile/dump LaTeX PREAMBLE text."
    (let ((preamble-hash
           (thread-first
             preamble
             (concat (plist-get info :latex-compiler)
                     (if tempfile-p "-temp" default-directory))
             (sha1)))
          (default-directory
            (if tempfile-p temporary-file-directory default-directory)))
      (or (cadr
           (org-persist-read "LaTeX format file cache"
                             (list :key preamble-hash)
                             nil nil :read-related t))
          (when-let* ((dump-file
                      (org-latex--precompile-preamble
                       info preamble
                       (expand-file-name preamble-hash temporary-file-directory))))
            (cadr
             (org-persist-register `(,"LaTeX format file cache"
                                     (file ,dump-file))
                                   (list :key preamble-hash)
                                   :write-immediately t)))))))

(unless (fboundp 'org-latex--remove-cached-preamble)
  (defun org-latex--remove-cached-preamble
      (latex-compiler preamble &optional tempfile-p)
    "Remove the cached preamble for PREAMBLE compiled with LATEX-COMPILER."
    (let ((preamble-hash
           (thread-first
             preamble
             (concat latex-compiler
                     (if tempfile-p "-temp" default-directory))
             (sha1))))
      (org-persist-unregister "LaTeX format file cache"
                              (list :key preamble-hash)
                              :remove-related t))))

(unless (fboundp 'org-latex--precompile-preamble)
  (defun org-latex--precompile-preamble (info preamble basepath)
    "Precompile PREAMBLE with mylatexformat."
    (let ((dump-file (concat basepath ".fmt"))
          (preamble-file (concat basepath ".tex"))
          (precompile-buffer
           (with-current-buffer
               (get-buffer-create org-latex--precompile-log)
             (erase-buffer)
             (current-buffer))))
      (with-temp-file preamble-file
        (insert preamble "\n\\endofdump\n"))
      (message "Precompiling Org LaTeX preamble...")
      (condition-case nil
          (org-compile-file
           preamble-file (list org-latex-precompile-command)
           "fmt" nil precompile-buffer
           (or (plist-get info :precompile-format-spec)
               `((?l . ,(plist-get info :latex-compiler))
                 (?L . ,(plist-get info :latex-compiler)))))
        (:success
         (kill-buffer precompile-buffer)
         (delete-file preamble-file)
         dump-file)
        (error
         (unless (= 0 (call-process "kpsewhich" nil nil nil "mylatexformat.ltx"))
           (display-warning
            '(org latex-preview preamble-precompilation)
            "The LaTeX package \"mylatexformat\" is required for precompilation, but could not be found"
            :warning))
         (unless (= 0 (call-process "kpsewhich" nil nil nil "preview.sty"))
           (display-warning
            '(org latex-preview preamble-precompilation)
            "The LaTeX package \"preview\" is required for precompilation, but could not be found"
            :warning))
         (display-warning
          '(org latex-preview preamble-precompilation)
          (format "Failed to precompile preamble (%s), see the \"%s\" buffer."
                  preamble-file precompile-buffer)
          :warning)
         nil)))))

(provide 'org-latex-preview-plus-compat)

;;; org-latex-preview-plus-compat.el ends here
