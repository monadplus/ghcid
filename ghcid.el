;;; ghcid.el Basic ghcid+cabal support in emacs -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2020 Arnau Abella
;;
;; Author: Arnau Abella <http://github/arnau>
;; Maintainer: Arnau Abella <arnauabella@gmail.com>
;; Created: octubre 07, 2020
;; Modified: octubre 07, 2020
;; Version: 0.0.1
;; Keywords:
;; Homepage: https://github.com/arnau/ghcid
;; Package-Requires: ((emacs 27.1) (cl-lib "0.5"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; Use M-x ghcid to launch
;;
;;; Code:

(require 'term)
(require 'compile)
(require 'haskell-mode) ; haskell-cabal-find-dir

;; TODO
;;  - Search for stack.yaml files

(setq ghcid-process-name "ghcid")

(define-minor-mode ghcid-mode
  "A minor mode for ghcid terminals

Use `ghcid' to start a ghcid session in a new buffer. The process
will start in the directory of your current buffer.

It is based on `compilation-mode'. That means the errors and
warnings can be clicked and the `next-error'(\\[next-error]) and
`previous-error'(\\[previous-error]) commands will work as usual.

To configure where the new buffer should appear, customize your
`display-buffer-alist'. For instance like so:

    (add-to-list
     \\='display-buffer-alist
     \\='(\"*ghcid*\"
       (display-buffer-reuse-window   ;; First try to reuse an existing window
        display-buffer-at-bottom      ;; Then try a new window at the bottom
        display-buffer-pop-up-window) ;; Otherwise show a pop-up
       (window-height . 18)      ;; New window will be 18 lines
       ))

If the window that shows ghcid changes size, the process will not
recognize the new height until you manually restart it by calling
`ghcid' again.
"
  :lighter " Ghcid"
  (when (fboundp 'nlinum-mode) (nlinum-mode -1))
  (linum-mode -1)
  (compilation-minor-mode))


;; Compilation mode does some caching for markers in files, but it gets confused
;; because ghcid reloads the files in the same process. Here we parse the
;; 'Reloading...' message from ghcid and flush the cache for the mentioned
;; files. This approach is very similar to the 'omake' hacks included in
;; compilation mode.
(add-to-list
  'compilation-error-regexp-alist-alist
  '(ghcid-reloading
    "Reloading\\.\\.\\.\\(\\(\n  .+\\)*\\)" 1 nil nil nil nil
    (0 (progn
         (let* ((filenames (cdr (split-string (match-string 1) "\n  "))))
           (dolist (filename filenames)
             (compilation--flush-file-structure filename)))
         nil))
    ))
(add-to-list 'compilation-error-regexp-alist 'ghcid-reloading)


(defun ghcid-buffer-name ()
  (concat "*" ghcid-process-name "*"))

(defun ghcid-ghci-cmd (target)
  (format "ghci %s" target))

(defun ghcid-stack-cmd (target)
  (format "stack ghci %s --test --bench --ghci-options=-fno-code" target))

(defun ghcid-cabal-cmd (target)
  (format "cabal repl %s --enable-tests --enable-benchmarks" target))

(defun ghcid-command (cmd height)
    (format "ghcid -c \"%s\" -h %s\n" cmd height))

(defun ghcid-get-buffer ()
  "Create or reuse a ghcid buffer with the configured name and
display it. Return the window that shows the buffer.

User configuration will influence where the buffer gets shown
exactly. See `ghcid-mode'."
  (display-buffer (get-buffer-create (ghcid-buffer-name)) '((display-buffer-reuse-window))))

(defun ghcid-start (mode filename dir)
  "Start ghcid in the specified directory"

  (with-selected-window (ghcid-get-buffer)

    (setq next-error-last-buffer (current-buffer))
    ;; https://github.com/haskell/haskell-mode/blob/4b72abe18ff7059d68e3a81c6daa13df2fdbd788/haskell-cabal.el#L298
    (setq-local default-directory
                (cond
                 ((= mode 2) (haskell-cabal-find-dir))
                 (t dir)))

    ;; Only now we can figure out the height to pass along to the ghcid process
    ;; (let ((height (- (window-body-size) 5)))
    (let ((height (- (window-height) scroll-margin 4))
          (ghcid-cmd (nth (- mode 1) '(ghcid-ghci-cmd ghcid-cabal-cmd ghcid-stack-cmd)))
          (ghcid-target (if (= mode 1) filename "")))

      ;; TODO this doesn't work
      ;; (when (/= mode 1)
      ;;   (message "Target: ")
      ;;   (read ghcid-target))
      (term-mode)
      (term-line-mode)  ;; Allows easy navigation through the buffer
      (ghcid-mode)

      (setq-local term-buffer-maximum-size height)
      (setq-local scroll-up-aggressively 1)
      (setq-local show-trailing-whitespace nil)

      (term-exec (ghcid-buffer-name)
           ghcid-process-name
           "/bin/bash"
           nil
           (list "-c" (ghcid-command (funcall ghcid-cmd ghcid-target) height)))

      )))

(defun ghcid-kill ()
  (let* ((ghcid-buf (get-buffer (ghcid-buffer-name)))
         (ghcid-proc (get-buffer-process ghcid-buf)))
    (delete-windows-on ghcid-buf)
    (when (processp ghcid-proc)
      (progn
        (set-process-query-on-exit-flag ghcid-proc nil)
        (kill-process ghcid-proc)
        ))))

;; TODO Close stuff if it fails
(defun ghcid (mode)
  "Start a ghcid process in a new window. Kills any existing sessions.
The process will be started in the directory of the buffer where
you ran this command from."
  (interactive "n(1) ghci (2) cabal (3) stack ")
  (let ((filename (buffer-file-name)))
    (if (or (< mode 1) (> mode 3))
        (error! "Wrong mode. Please choose (1), (2) or (3)")
      (ghcid-start mode filename default-directory))))

;; Assumes that only one window is open
(defun ghcid-stop ()
  "Stop ghcid"
  (interactive)
  (ghcid-kill)
  (kill-buffer (ghcid-buffer-name)))

(provide 'ghcid)

;;; ghcid.el ends here
