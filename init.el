;;; init.el --- Stante Pede: Instantly awesome Emacs -*- lexical-binding: t; -*-
;;
;; Copyright (c) 2012, 2013 Sebastian Wiesner
;;
;; Author: Sebastian Wiesner <lunaryorn@gmail.com>
;; URL: https://gihub.com/lunaryorn/stante-pede.git
;; Keywords: convenience

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation; either version 3 of the License, or (at your option) any later
;; version.

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.

;; You should have received a copy of the GNU General Public License along with
;; GNU Emacs; see the file COPYING.  If not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
;; USA.


;;; Commentary:

;; My personal Emacs configuration.

;;; Code:


;; Guard against Emacs 24
(when (or (< emacs-major-version 24)
          (and (= emacs-major-version 24) (< emacs-minor-version 3)))
  (error "Stante Pede needs at least GNU Emacs 24.3, but this is Emacs %s.
Please install GNU Emacs 24.3 to use Stante Pede"
         emacs-version))


;;;; Package management

(package-initialize)

;; Load the Carton file to add our package sources
(require 'carton)
(carton-setup user-emacs-directory)

(defconst stante-vendor-dir (locate-user-emacs-file "vendor")
  "Directory for embedded 3rd party extensions.")


;;;; Requires

(require 'dash)
(require 's)
(require 'bind-key)


;;;; Package configuration and initialization

(defmacro stante-after (feature &rest forms)
  "After FEATURE is loaded, evaluate FORMS.

FORMS is byte compiled.

FEATURE may be a named feature or a file name, see
`eval-after-load' for details."
  (declare (indent 1) (debug t))
  ;; Byte compile the body.  If the feature is not available, ignore warnings.
  ;; Taken from
  ;; http://lists.gnu.org/archive/html/bug-gnu-emacs/2012-11/msg01262.html
  `(,(if (or (not byte-compile-current-file)
             (if (symbolp feature)
                 (require feature nil :no-error)
               (load feature :no-message :no-error)))
         'progn
       (message "stante-after: cannot find %s" feature)
       'with-no-warnings)
    (eval-after-load ',feature
      `(funcall (function ,(lambda () ,@forms))))))

(defun stante-auto-modes (&rest modes-and-patterns)
  "Add MODES-AND-PATTERNS to `auto-mode-alist'.

MODES-AND-PATTERNS is of the form `(mode1 pattern1 pattern2 …
mode2 pattern3 pattern4)'.  For each major mode symbol, add auto
mode entries for all subsequent patterns until the next major
mode symbol."
  (--each (-partition-by-header #'symbolp modes-and-patterns)
    (pcase-let ((`(,mode . ,patterns) it))
      (--each patterns
        (add-to-list 'auto-mode-alist (cons it mode))))))

(defconst stante-font-lock-keywords
  `((,(eval-when-compile (concat "(" (regexp-opt '("stante-after"
                                                   "stante-auto-modes")
                                                 'symbols)
                                 "\\s-+\\_<\\(\\(?:\\sw\\|\\s_\\)+\\)\\_>"))
     (1 font-lock-keyword-face)
     (2 font-lock-constant-face)))
  "Our font lock keywords for Lisp modes.")

(stante-after lisp-mode
  (--each '(emacs-lisp-mode lisp-interaction-mode)
    (font-lock-add-keywords it stante-font-lock-keywords :append)))

(stante-after ielm
  (font-lock-add-keywords 'inferior-emacs-lisp-mode
                          stante-font-lock-keywords :append))


;;;; Environment fixup
(stante-after exec-path-from-shell
  (add-to-list 'exec-path-from-shell-variables "EMAIL"))

(when (and (not (eq system-type 'windows-nt)) (display-graphic-p))
  (exec-path-from-shell-initialize)

  (-when-let (email (getenv "EMAIL"))
    (setq user-mail-address email)))


;; the custom file
(defconst stante-custom-file (locate-user-emacs-file "custom.el")
  "File used to store settings from Customization UI.")

(stante-after cus-edit
  (setq custom-file stante-custom-file))

(load stante-custom-file :no-error :no-message)


;; OS X support

(stante-after ns-win
  (setq ns-pop-up-frames nil            ; Don't pop up new frames from the
                                        ; workspace
        mac-option-modifier 'meta       ; Option is simply the natural Meta
        mac-command-modifier 'meta      ; But command is a lot easier to hit
        mac-right-option-modifier 'none ; Keep right option for accented input
        ;; Just in case we ever need these keys
        mac-function-modifier 'hyper
        mac-right-command-modifier 'super))

;; Prefer GNU utilities over the inferior BSD variants.  Also improves
;; integration with Emacs (for instance, GNU ls has a special --dired flag to
;; support dired)
(when (eq system-type 'darwin)
  ;; GNU ls
  (-if-let (gls (executable-find "gls")) (setq insert-directory-program gls)
           (message "GNU Coreutils not found.  Install coreutils with homebrew."))
  ;; GNU find
  (-when-let (gfind (executable-find "gfind"))
    (setq find-program gfind)))

;; Utility functions for OS X
(defun stante-id-of-bundle (bundle)
  "Get the ID of a BUNDLE.

BUNDLE is the user-visible name of the bundle as string.  Return
the id of the bundle as string.

These bundle IDs are normally constant.  Thus you may use this
function to determine the ID once, and then hard-code it in your
code."
  (let ((script (format "id of app \"%s\"" bundle)))
    (car (process-lines "osascript" "-e" script))))

(defun stante-path-of-bundle (id)
  "Get the path of a bundle with ID.

ID is the bundle ID (see `stante-id-of-bundle' as string.  Return
the directory path of the bundle as string."
  (let ((query (format "kMDItemCFBundleIdentifier == '%s'" id)))
    (car (process-lines "mdfind" query))))

(defun stante-homebrew-prefix (&optional formula)
  "Get the homebrew prefix for FORMULA.

Without FORMULA, get the homebrew prefix itself.

Return nil, if homebrew is not available, or if the prefix
directory does not exist."
  (let ((prefix (condition-case nil
                    (car (apply #'process-lines "brew" "--prefix"
                                (when formula (list formula))))
                  (error nil))))
    (when (and prefix (file-directory-p prefix))
      prefix)))

(defun stante-homebrew-installed-p (&optional formula)
  "Determine whether a homebrew FORMULA is installed.

Without FORMULA determine whether Homebrew itself is available."
  (if formula
      (when (stante-homebrew-prefix formula) t)
    (when (executable-find "brew") t)))


;;;; User interface

;; Get rid of tool bar and menu bar, except on OS X, where the menu bar is
;; present anyway, so disabling it is pointless
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))
(unless (eq system-type 'darwin)
  (when (fboundp 'menu-bar-mode)
    (menu-bar-mode -1)))

;; No blinking and beeping, no startup screen and short Yes/No questions
(blink-cursor-mode -1)
(setq ring-bell-function 'ignore
      inhibit-startup-screen t)
(fset 'yes-or-no-p 'y-or-n-p)

;; Choose Font and color theme.  We try to use Anonymous Pro from
;; http://www.marksimonson.com/fonts/view/anonymous-pro or Inconsolata (from the
;; Google Webfont directory).  On OS X, we need to give these fonts a larger
;; size.  If neither is available, we fall back to the standard faces of OS X
;; (Menlo), Linux (DejaVu Sans Mono) or Windows (Consolas, Courier New)
(defconst stante-preferred-monospace-fonts
  `(("Anonymous Pro" . ,(if (eq system-type 'darwin) 140 110))
    ("Anonymous Pro Minus" . ,(if (eq system-type 'darwin) 140 110))
    ("Inconsolata" . ,(if (eq system-type 'darwin) 140 110))
    ("Menlo" . 130)
    ("Consolas" . 130)
    ("DejaVu Sans Mono" 110)
    ("Courier New" . 130))
  "Preferred monospace fonts for Stante.

The `car' of each item is the font family, the `cdr' the preferred font size.")

(defun stante-first-existing-font (fonts)
  "Get the first existing font from FONTS."
  (--first (x-family-fonts (car it)) fonts))

(defun stante-choose-best-fonts ()
  "Choose the best fonts."
  (interactive)
  (-when-let (font  (stante-first-existing-font stante-preferred-monospace-fonts))
    (--each '(default fixed-pitch)
      (set-face-attribute it nil :family (car font) :height (cdr font)))))

(stante-choose-best-fonts)
(load-theme 'solarized-light :no-confirm)
;; (load-theme 'solarized-dark :no-confirm)
;; (load-theme 'zenburn :no-confirm)


;;;; The mode line

(line-number-mode t)
(column-number-mode t)
(size-indication-mode t)


;;;; The minibuffer

;; Save a minibuffer input history
(stante-after savehist
  (setq savehist-save-minibuffer-history t
        savehist-autosave-interval 180))
(savehist-mode t)

;; Boost file and buffer operations by flexible matching and the ability to
;; perform operations like deleting files or killing buffers directly from the
;; minibuffer
(stante-after ido
  (setq ido-enable-flex-matching t      ; Match characters if string doesn't
                                        ; match
        ido-create-new-buffer 'always   ; Create a new buffer if nothing matches
        ido-use-filename-at-point 'guess
        ido-default-file-method 'selected-window)

  ;; Boost all `completing-read's with IDO
  (stante-after ido-ubiquitous
    ;; Disable for some AUCTeX commands because it breaks the easy selection of
    ;; the default value
    (ido-ubiquitous-disable-in TeX-command-master)
    (ido-ubiquitous-disable-in LaTeX-section)))
(ido-mode t)
(ido-ubiquitous-mode)                   ; Use IDO everywhere
(ido-vertical-mode)                     ; Show IDO completions vertically

;; Configure Smex
(stante-after smex
  (setq smex-save-file (locate-user-emacs-file ".smex-items")))


;;;; Buffer management

;; De-duplicate buffer names by prepending parts of the directory until the name
;; is unique, instead of just appending numbers.
(require 'uniquify)
(setq uniquify-buffer-name-style 'forward
      uniquify-after-kill-buffer-p t
      uniquify-ignore-buffers-re "^\\*") ; Do not rename special buffers!

;; Clean stale buffers
(require 'midnight)


;; Window management

;; Move between windows with Shift + Arrow keys
(windmove-default-keybindings)

;; Undo and redo window configurations with C-c Left and C-c Right respectively
(winner-mode)

;; Prevent Ediff from spamming the frame
(stante-after ediff-wind
  (setq ediff-window-setup-function 'ediff-setup-windows-plain))

;; A utility command to quickly switch buffers, see
;; http://emacsredux.com/blog/2013/04/28/switch-to-previous-buffer/
(defun stante-switch-to-previous-buffer ()
  "Switch to the previous buffer.

Repeated invocations toggle between the two most recently used
buffers."
  (interactive)
  (switch-to-buffer (other-buffer (current-buffer) :visible-ok)))


;;;; Frames

;; A reasonable frame title
(setq frame-title-format
      '(:eval (if (buffer-file-name)
                  (abbreviate-file-name (buffer-file-name)) "%b")))

;; Save and restore frame parameters
(defvar stante-save-frame-parameters-file
  (locate-user-emacs-file ".frame-parameters" )
  "File in which to storce frame parameters on exit.")

(defconst stante-frame-parameters-to-save
  '(left top width height maximized fullscreen)
  "Frame parameters to save and restore for the initial frame.")

(defun stante-save-frame-parameters ()
  "Save frame parameters of the selected frame.

Save selected parameters (see `stante-frame-parameters-to-save')
to `stante-save-frame-parameters-file'."
  (condition-case nil
      (let ((params (--filter (memq (car it) stante-frame-parameters-to-save)
                              (frame-parameters))))
        (when (and params (display-graphic-p)) ; GUI frames only!
          (with-temp-file stante-save-frame-parameters-file
            (prin1 params (current-buffer))
            (terpri (current-buffer)))
          t))
    (file-error nil)))

(defun stante-restore-frame-parameters ()
  "Restore the frame parameters of the initial frame."
  (condition-case nil
      (-when-let* ((read-params
                    (with-temp-buffer
                      (insert-file-contents stante-save-frame-parameters-file)
                      (goto-char (point-min))
                      (read (current-buffer))))
                   (allowed-params
                    (--filter (memq (car it) stante-frame-parameters-to-save)
                              read-params)))
        (setq initial-frame-alist
              (append (--filter (assq (car it) allowed-params) initial-frame-alist)
                      allowed-params nil)))
    (error nil)))

(unless noninteractive
  (add-hook 'kill-emacs-hook 'stante-save-frame-parameters)
  (add-hook 'after-init-hook 'stante-restore-frame-parameters))


;;;; File handling

;; Keep backup and auto save files out of the way
(setq backup-directory-alist `((".*" . ,(locate-user-emacs-file ".backup")))
      auto-save-file-name-transforms `((".*" ,temporary-file-directory t)))

;; Store Tramp auto save files locally
(stante-after tramp
  (setq tramp-auto-save-directory (locate-user-emacs-file "tramp-auto-save")))

;; Power up dired
(stante-after dired (require 'dired-x))

;; Update copyright when visiting files
(add-hook 'find-file-hook 'copyright-update)

;; Ignore uninteresting files
(ignoramus-setup)

;; Do not clobber user writeable files
(stante-after hardhat
  ;; Add local homebrew prefix to the list of protected directories.  Hardhat
  ;; itself only handles /usr/local/
  (when (eq system-type 'darwin)
    (-when-let (prefix (stante-homebrew-prefix))
      (add-to-list 'hardhat-fullpath-protected-regexps prefix))))
(global-hardhat-mode)

;; Save bookmarks immediately after a bookmark was added
(stante-after bookmark
  (setq bookmark-save-flag 1))

;; Track recent files
(stante-after recentf
  (setq recentf-max-saved-items 200
        recentf-max-menu-items 15))
(recentf-mode t)

;; Open recent files with IDO, see
;; http://emacsredux.com/blog/2013/04/05/recently-visited-files/
(stante-after recentf
  (defun stante-ido-find-recentf ()
    "Find a recent file with IDO."
    (interactive)
    (let ((file (ido-completing-read "Find recent file: " recentf-list nil t)))
      (when file
        (find-file file)))))

;; Save position in files
(require 'saveplace)
(setq-default save-place t)

;; View files read-only
(setq view-read-only t)

;; Automatically revert files on external changes (e.g. git checkout)
(global-auto-revert-mode 1)

;; Utility commands for working with files, see:
;; http://emacsredux.com/blog/2013/03/27/open-file-in-external-program/
;; http://emacsredux.com/blog/2013/05/04/rename-file-and-buffer/
;; http://emacsredux.com/blog/2013/04/03/delete-file-and-buffer/
;; http://emacsredux.com/blog/2013/03/27/copy-filename-to-the-clipboard/
;; https://github.com/bbatsov/prelude/blob/master/core/prelude-core.el
(defun stante-get-standard-open-command ()
  "Get the standard command to open a file.

Return the command as shell command, or nil if there is no standard command
for the current platform."
  (cond
   ((eq system-type 'darwin) "open")
   ((memq system-type '(gnu gnu/linux gnu/kfreebsd)) "xdg-open")))

(defun stante-open-with (arg)
  "Open the file visited by the current buffer externally.

Use the standard program to open the file.  With prefix ARG,
prompt for the command to use."
  (interactive "P")
  (unless (buffer-file-name)
    (user-error "This buffer is not visiting a file"))
  (let ((command (unless arg (stante-get-standard-open-command))))
    (unless command
      (setq command (read-shell-command "Open current file with: ")))
    (shell-command (concat command " "
                           (shell-quote-argument (buffer-file-name))))))

(defun stante-copy-filename-as-kill (&optional arg)
  "Copy the name of the currently visited file to kill ring.

With a zero prefix arg, copy the absolute file name.  With
\\[universal-argument], copy the file name relative to the
current buffer's `default-directory'.  Otherwise copy the
non-directory part only."
  (interactive "P")
  (-if-let* ((filename (if (eq major-mode 'dired-mode)
                           default-directory
                         (buffer-file-name)))
             (name-to-copy (cond ((zerop (prefix-numeric-value arg)) filename)
                                 ((consp arg) (file-relative-name filename))
                                 (:else (file-name-nondirectory filename)))))
    (progn
      (kill-new name-to-copy)
      (message "%s" name-to-copy))
    (user-error "This buffer is not visiting a file")))

(defun stante-rename-file-and-buffer ()
  "Rename the current file and buffer."
  (interactive)
  (let* ((filename (buffer-file-name))
         (old-name (if filename
                       (file-name-nondirectory filename)
                     (buffer-name)))
         (new-name (read-file-name "New name: " nil nil nil old-name)))
    (cond
     ((not (and filename (file-exists-p filename))) (rename-buffer new-name))
     ((vc-backend filename) (vc-rename-file filename new-name))
     (:else
      (rename-file filename new-name :force-overwrite)
      (set-visited-file-name new-name :no-query :along-with-file)))))

(defun stante-delete-file-and-buffer ()
  "Delete the current file and kill the buffer."
  (interactive)
  (let ((filename (buffer-file-name)))
    (cond
     ((not filename) (kill-buffer))
     ((vc-backend filename) (vc-delete-file filename))
     (:else
      (delete-file filename)
      (kill-buffer)))))

;; Quickly edit init.el
(defun stante-find-user-init-file-other-window ()
  "Edit the `user-init-file', in another window."
  (interactive)
  (find-file-other-window user-init-file))


;;;; Basic editing

;; Decent coding system
(prefer-coding-system 'utf-8)

;; Drag stuff around with Meta-Shift-Arrows
(stante-after drag-stuff
  (setq drag-stuff-modifier '(meta shift))

  ;; Drag Stuff is incompatible with Org, because it shadows many useful Org
  ;; bindings.  This doesn't do much harm, because Org has its own structural
  ;; movement commands
  (add-to-list 'drag-stuff-except-modes 'org-mode)

  (diminish 'drag-stuff-mode "⇅"))
(drag-stuff-global-mode)

;; Make `kill-whole-line' indentation aware
(defun stante-smart-kill-whole-line (&optional arg)
  "Kill whole line and move back to indentation.

Kill the whole line with function `kill-whole-line' and then move
`back-to-indentation'."
  (interactive "p")
  (kill-whole-line arg)
  (back-to-indentation))

;; Some other utilities
(defun stante-smart-backward-kill-line ()
  "Kill line backwards and re-indent."
  (interactive)
  (kill-line 0)
  (indent-according-to-mode))

(defun stante-smart-open-line ()
  "Insert empty line after the current line."
  (interactive)
  (move-end-of-line nil)
  (newline-and-indent))

;; Make C-a toggle between beginning of line and indentation
(defun stante-back-to-indentation-or-beginning-of-line (arg)
  "Move point back to indentation of beginning of line.

Move point to the first non-whitespace character on this line.
If point is already there, move to the beginning of the line.
Effectively toggle between the first non-whitespace character and
the beginning of the line.

If ARG is not nil or 1, move forward ARG - 1 lines first.  If
point reaches the beginning or end of the buffer, stop there."
  (interactive "^p")
  (setq arg (or arg 1))

  ;; Move lines first
  (when (/= arg 1)
    (let ((line-move-visual nil))
      (forward-line (1- arg))))

  (let ((orig-point (point)))
    (back-to-indentation)
    (when (= orig-point (point))
      (move-beginning-of-line 1))))

;; A missing autoload
(autoload 'zap-up-to-char "misc"
  "Kill up to, but not including ARGth occurrence of CHAR.")

;; Disable tabs, but given them proper width
(setq-default indent-tabs-mode nil
              tab-width 8)
;; Make Tab complete if the line is indented
(setq tab-always-indent 'complete)

;; Highlight bad whitespace
(stante-after whitespace
  (diminish 'whitespace-mode "␣")
  ;; Highlight tabs, empty lines at beg/end, trailing whitespaces and overlong
  ;; portions of lines via faces.  Also indicate tabs via characters
  (setq whitespace-style '(face tabs tab-mark empty trailing lines-tail)
        whitespace-line-column nil))    ; Use `fill-column' for overlong lines
;; Indicate empty lines at the end of a buffer in the fringe
(setq indicate-empty-lines t)

;; Rigidly cleanup whitespace in programming modes
(define-minor-mode stante-prog-whitespace-mode
  "Minor mode to highlight and cleanup whitespace."
  :lighter nil
  :keymap nil
  (cond
   (stante-prog-whitespace-mode
    (whitespace-mode 1)
    (add-hook 'before-save-hook 'whitespace-cleanup nil :local))
   (:else
    (whitespace-mode -1)
    (remove-hook 'before-save-hook 'whitespace-cleanup :local))))
(add-hook 'prog-mode-hook 'stante-prog-whitespace-mode)

;; In plain text, only cleanup trailing whitespace
(define-minor-mode stante-text-whitespace-mode
  "Minor mode to highlight and cleanup whitespace."
  :lighter nil
  :keymap nil
  (cond
   (stante-text-whitespace-mode
    (whitespace-mode 1)
    (add-hook 'before-save-hook 'delete-trailing-whitespace nil :local))
   (:else
    (whitespace-mode -1)
    (remove-hook 'before-save-hook 'delete-trailing-whitespace :local))))
(add-hook 'text-mode-hook 'stante-text-whitespace-mode)

;; A function to disable highlighting of long lines in modes
(stante-after whitespace
  (defun stante-whitespace-style-no-long-lines ()
    "Configure `whitespace-mode' for Org.

Disable the highlighting of overlong lines."
    (setq-local whitespace-style (-difference whitespace-style
                                              '(lines lines-tail)))
    (when whitespace-mode
      (whitespace-mode -1)
      (whitespace-mode 1))))

;; Delete the selection instead of inserting
(delete-selection-mode)

;; Wrap the region with delimiters
(stante-after wrap-region

  (defun stante-add-wrapper-for-pair (pair &optional mode)
    "Add a Wrap Region wrapper for PAIR in MODE.

PAIR is an electric pair, just like for `electric-pair-pairs'.
MODE is the major mode to add the wrapper for, defaulting to the
current major mode."
    (wrap-region-add-wrapper (string (car pair)) (string (cdr pair))
                             nil (or mode major-mode)))

  (defun stante-add-region-wrappers-from-pairs ()
    "Add Wrap Region wrappers from electric pairs.

Add all explicit wrappers defined in `electric-pair-pairs' as
Wrap Region wrappers for the current major mode."
    (when (boundp 'electric-pair-pairs)
      (-each electric-pair-pairs #'stante-add-wrapper-for-pair)))

  (add-hook #'wrap-region-mode-hook #'stante-add-region-wrappers-from-pairs)

  (diminish 'wrap-region-mode "<>"))

(wrap-region-global-mode)

;; Save the contents of the clipboard to kill ring before killing, except on OS
;; X where this behaviour is broken because it causes errors to be signaled
;; whenever the clipboard is empty :|
(when (not (eq system-type 'darwin))
  (setq save-interprogram-paste-before-kill t))

;; Configure a reasonable fill column, indicate it in the buffer and enable
;; automatic filling
(setq-default fill-column 80)
(--each '(prog-mode-hook text-mode-hook)
  (add-hook it 'fci-mode))
(add-hook 'text-mode-hook 'turn-on-auto-fill)

(define-minor-mode stante-auto-fill-comments-mode
  "Minor mode to auto-fill comments only."
  :lighter nil
  :keymap nil
  (cond
   (stante-auto-fill-comments-mode
    (setq-local comment-auto-fill-only-comments t)
    (auto-fill-mode 1))
   (:else
    (kill-local-variable 'comment-auto-fill-only-comments)
    (auto-fill-mode -1))))
(add-hook 'prog-mode-hook 'stante-auto-fill-comments-mode)

;; Choose wrap prefix automatically
(add-hook 'visual-line-mode-hook 'adaptive-wrap-prefix-mode)

;; Configure scrolling
(setq scroll-margin 0                   ; Drag the point along while scrolling
      scroll-conservatively 1000        ; Never recenter the screen while scrolling
      scroll-error-top-bottom t         ; Move to beg/end of buffer before
                                        ; signalling an error
      ;; These settings make trackpad scrolling on OS X much more predictable
      ;; and smooth
      mouse-wheel-progressive-speed nil
      mouse-wheel-scroll-amount '(1))

;; Give us narrowing back!
(put 'narrow-to-region 'disabled nil)
(put 'narrow-to-page 'disabled nil)
(put 'narrow-to-defun 'disabled nil)

;; Same for region casing
(put 'upcase-region 'disabled nil)
(put 'downcase-region 'disabled nil)

;; Automatically pairs parenthesis, and provide a function to define local
;; pairs.
(require 'electric)
(electric-pair-mode)

(defun stante-add-local-electric-pairs (pairs)
  "Add buffer-local electric PAIRS."
  (setq-local electric-pair-pairs (append pairs electric-pair-pairs nil)))

;; Highlight the current line, editing operations in the buffer, and matching
;; parenthesis
(global-hl-line-mode 1)
(require 'volatile-highlights)          ; Doesn't autoload :|
(diminish 'volatile-highlights-mode)
(volatile-highlights-mode t)
(show-paren-mode)

;; Power up undo
(stante-after undo-tree (diminish 'undo-tree-mode "⤺"))
(global-undo-tree-mode)

;; Nicify page breaks
(stante-after page-break-lines (diminish 'page-break-lines-mode))
(global-page-break-lines-mode)

;; On the fly syntax checking
(global-flycheck-mode)

;; An Emacs server for `emacsclient'
(require 'server)
(unless (server-running-p) (server-start))


;;;; Completion and expansion

;; Configured hippie-expand reasonably
(stante-after hippie-exp
  (setq hippie-expand-try-functions-list
        '(try-expand-dabbrev
          try-expand-dabbrev-all-buffers
          try-expand-dabbrev-from-kill
          try-complete-file-name-partially
          try-complete-file-name
          try-expand-all-abbrevs
          try-expand-list
          try-expand-line
          try-complete-lisp-symbol-partially
          try-complete-lisp-symbol)))

;; Expandable text snippets
(stante-after yasnippet (diminish 'yas-minor-mode "…"))
(yas-global-mode)

;; In `completion-at-point', do not pop up silly completion buffers for less
;; than five candidates.  Cycle instead.
(setq completion-cycle-threshold 5)

;; Enable auto-completion
(stante-after company
  (diminish 'company-mode "•")

  ;; Make auto completion a little less aggressive.
  (setq company-idle-delay 1.0
        company-begin-commands '(self-insert-command)
        company-show-numbers t))        ; Easy navigation to candidates with
                                        ; M-<n>
(global-company-mode)


;;;; Spell checking

;; Warn if the spell checker is missing
(unless (executable-find "aspell")
  (message "Aspell not found.  Spell checking may not be available!"))

(stante-after ispell
  (setq ispell-dictionary "en"          ; Default dictionary
        ispell-silently-savep t))       ; Don't ask when saving the private dict

(stante-after flyspell
  ;; Free M-Tab and C-M-i, and never take it again!
  (define-key flyspell-mode-map "\M-\t" nil)
  (setq flyspell-use-meta-tab nil
        ;; Make Flyspell less chatty
        flyspell-issue-welcome-flag nil
        flyspell-issue-message-flag nil)

  (diminish 'flyspell-mode "✓"))

(--each '(text-mode-hook message-mode-hook)
  (add-hook it 'turn-on-flyspell))
(add-hook 'prog-mode-hook 'flyspell-prog-mode)


;;;; AUCTeX

;; Load AUCTeX from package manager, because the ELPA package is out-dated
(when (and (eq system-type 'darwin) (stante-homebrew-installed-p "auctex"))
  (let ((homebrew-prefix (stante-homebrew-prefix)))
    (add-to-list 'load-path (expand-file-name "share/emacs/site-lisp"
                                              homebrew-prefix))))

(require 'tex-site nil :no-error)
(require 'preview-latex nil :no-error)

;; Some standard defaults
(stante-after tex
  (setq TeX-parse-self t                ; Parse documents to provide completion
                                        ; for packages, etc.
        TeX-auto-save t                 ; Automatically save
        TeX-clean-confirm nil           ; Do not ask for confirmation when
                                        ; cleaning
        ;; Provide forward and inverse search with SyncTeX
        TeX-source-correlate-mode t
        TeX-source-correlate-method 'synctex)
  (setq-default TeX-master nil          ; Ask for the master file
                TeX-engine 'luatex      ; Use a modern engine
                TeX-PDF-mode t)         ; Create PDFs by default

  ;; Replace the rotten Lacheck with Chktex
  (setcar (cdr (assoc "Check" TeX-command-list)) "chktex -v6 %s")

  ;; Build with Latexmk
  (unless (boundp 'TeX-command-latexmk)
    (defvar TeX-command-latexmk "latexmk"
      "The name of the latexmk command.")

    (unless (assoc TeX-command-latexmk TeX-command-list)
      (add-to-list 'TeX-command-list
                   `(,TeX-command-latexmk "latexmk" TeX-run-command t t
                                          :Help "Run latexmk")))))


(stante-after latex

  (--each '(LaTeX-math-mode             ; Easy math input
            reftex-mode)                ; Cross references on steroids
    (add-hook 'LaTeX-mode-hook it))

  (--each '("\\.fdb_latexmk" "\\.fls")
    (add-to-list 'LaTeX-clean-intermediate-suffixes it)))

;; Find Skim.app on OS X, for Sycntex support which Preview.app lacks.
(defun stante-find-skim-bundle ()
    "Return the location of the Skim bundle, or nil if Skim is not installed.

Skim is an advanced PDF viewer for OS X with SyncTex support.
See http://skim-app.sourceforge.net/ for more information."
    (stante-path-of-bundle "net.sourceforge.skim-app.skim"))

  (defun stante-find-skim-displayline ()
    "Return the path of the displayline frontend of Skim.

Return nil if Skim is not installed.  See `stante-find-skim-bundle'."
    (-when-let (skim-bundle (stante-find-skim-bundle))
      (executable-find (expand-file-name "Contents/SharedSupport/displayline"
                                         skim-bundle))))

(stante-after tex
  (defun stante-TeX-find-view-programs-os-x ()
    "Find TeX view programs on OS X.

Populate `TeX-view-program-list' with installed viewers."
    ;; The default application, usually Preview
    (add-to-list 'TeX-view-program-list
                 '("Default application" "open %o"))
    ;; Skim if installed
    (-when-let (skim-displayline (stante-find-skim-displayline))
      (add-to-list 'TeX-view-program-list
                   `("Skim" (,skim-displayline " -b -r %n %o %b")))))

  (defun stante-TeX-select-view-programs-os-x ()
    "Select the best view programs on OS X.

Choose Skim if available, or fall back to the default application."
    ;; Find view programs
    (stante-TeX-find-view-programs-os-x)
    (setq TeX-view-program-selection
          `((output-dvi "Default application")
            (output-html "Default application")
            ;; Use Skim if installed for SyncTex support.
            (output-pdf ,(if (assoc "Skim" TeX-view-program-list)
                             "Skim" "Default application")))))

  (defun stante-TeX-select-view-programs ()
    "Select the best view programs for the current platform."
    (when (eq system-type 'darwin)
      (stante-TeX-select-view-programs-os-x)))

  ;; Select best viewing programs
  (stante-TeX-select-view-programs))

;; Configure BibTeX
(stante-after bibtex
  (bibtex-set-dialect 'biblatex)        ; Use a modern dialect
  ;; Exhaustive cleanup and reformatting of entries, to keep Bibtex files in
  ;; good shape
  (setq bibtex-entry-format '(opts-or-alts
                              required-fields
                              numerical-fields
                              whitespace
                              realign
                              last-comma
                              delimiters
                              unify-case
                              strings
                              sort-fields)))

;; Configure RefTeX
(stante-after reftex
  (setq reftex-plug-into-AUCTeX t       ; Plug into AUCTeX
        ;; Recommended optimizations
        reftex-enable-partial-scans t
        reftex-save-parse-info t
        reftex-use-multiple-selection-buffers t)

  ;; Provide basic RefTeX support for biblatex
  (unless (assq 'biblatex reftex-cite-format-builtin)
    (add-to-list 'reftex-cite-format-builtin
                 '(biblatex "The biblatex package"
                            ((?\C-m . "\\cite[]{%l}")
                             (?t . "\\textcite{%l}")
                             (?a . "\\autocite[]{%l}")
                             (?p . "\\parencite{%l}")
                             (?f . "\\footcite[][]{%l}")
                             (?F . "\\fullcite[]{%l}")
                             (?x . "[]{%l}")
                             (?X . "{%l}"))))
    (setq reftex-cite-format 'biblatex)))

;; Plug reftex into bib-cite
(stante-after bib-cite
  (setq bib-cite-use-reftex-view-crossref t)) ; Plug into bibcite


;;;; Markdown editing

;; Why doesn't Markdown Mode do this itself?!
(stante-auto-modes 'markdown-mode "\\.md\\'" "\\.markdown\\'")

;; Find a suitable processor
(stante-after markdown-mode
  (defconst stante-markdown-commands
    '(("kramdown")
      ("markdown2" "-x" "fenced-code-blocks")
      ("pandoc"))
    "Markdown processors we try to use.")

  (defun stante-find-markdown-processor ()
    "Find a suitable markdown processor.

Search for a suitable markdown processor using
`stante-markdown-commands' and set `markdown-command' properly.

Return the new `markdown-command' or signal an error if no
suitable processor was found."
    (interactive)
    ;; Clear previous command
    (setq markdown-command
          (mapconcat #'shell-quote-argument
                     (--first (executable-find (car it)) stante-markdown-commands)
                     " "))
    (unless markdown-command
      (error "No markdown processor found"))
    markdown-command)

  (stante-find-markdown-processor)

  ;; Teach electric-pair-mode about Markdown pairs
  (defun stante-markdown-electric-pairs ()
    "Add buffer-local electric pairs for Markdown."
    (stante-add-local-electric-pairs '((?* . ?*)
                                       (?` . ?`))))

  (--each '(markdown-mode-hook gfm-mode-hook)
    (add-hook it #'stante-markdown-electric-pairs)))

;; Don't do filling in GFM mode, where line breaks are significant, and do not
;; highlight overlong lines.  Instead enable visual lines.
(stante-after markdown-mode
  (--each '(turn-off-fci-mode turn-off-auto-fill visual-line-mode)
    (add-hook 'gfm-mode-hook it))

  (stante-after whitespace
    (add-hook 'gfm-mode-hook #'stante-whitespace-style-no-long-lines)))


;;;; Symbol “awareness”

;; Highlight the symbol under point
(stante-after highlight-symbol
  (setq highlight-symbol-idle-delay 0.4 ; Highlight almost immediately
        highlight-symbol-on-navigation-p t) ; Highlight immediately after
                                            ; navigation
  (diminish 'highlight-symbol-mode))
(add-hook 'prog-mode-hook 'highlight-symbol-mode)


;;;; Basic Lisp editing

(defvar stante-lisp-common-modes
  '(paredit-mode                        ; Edit Sexps not strings
    rainbow-delimiters-mode)            ; Color parenthesis according to nesting
  "Common modes for Lisp editing.")

(stante-after rainbow-delimiters (diminish 'rainbow-delimiters-mode))
(stante-after paredit (diminish 'paredit-mode "π"))


;;;; Emacs Lisp

;; Teach Emacs about Emacs scripts and Carton files
(add-to-list 'interpreter-mode-alist '("emacs" . emacs-lisp-mode))
(stante-auto-modes 'emacs-lisp-mode "/Carton\\'")

;; Enable some common Emacs Lisp helper modes
(defvar stante-emacs-lisp-common-modes
  (append
   '(turn-on-eldoc-mode                 ; Show function signatures in echo area
     elisp-slime-nav-mode)              ; Navigate to symbol definitions
   stante-lisp-common-modes)
  "Common modes for Emacs Lisp editing.")
(stante-after lisp-mode
  (--each stante-emacs-lisp-common-modes
    (add-hook 'emacs-lisp-mode-hook it)
    (add-hook 'lisp-interaction-mode-hook it)))
(stante-after ielm
  (--each stante-emacs-lisp-common-modes
    (add-hook 'ielm-mode-hook it)))

(stante-after lisp-mode
  (--each '(checkdoc-minor-mode         ; Check doc conventions when eval'ing
                                        ; expressions
            auto-compile-mode)          ; Automatically compile after save
    (add-hook 'emacs-lisp-mode-hook it))

  ;; Teach Electric about Emacs Lisp pairs
  (defun stante-emacs-lisp-electric-pairs ()
    "Add electric pairs for Emacs Lisp."
    (stante-add-local-electric-pairs '((?` . ?'))))
  (add-hook 'emacs-lisp-mode-hook #'stante-emacs-lisp-electric-pairs)

  ;; Load ERT to support unit test writing and running
  (require 'ert))

;; Indicate Auto Compile mode
(stante-after auto-compile (diminish 'auto-compile-mode "⏎"))

;; Now de-clutter the mode line
(stante-after eldoc (diminish 'eldoc-mode))
(stante-after checkdoc (diminish 'checkdoc-minor-mode))
(stante-after elisp-slime-nav (diminish 'elisp-slime-nav-mode "↪"))


;;;; Clojure

;; Enable some common Clojure helper modes
(defvar stante-clojure-common-modes
  (append '(subword-mode) stante-lisp-common-modes))

(stante-after clojure-mode
  (--each stante-clojure-common-modes
    (add-hook 'clojure-mode-hook it))

  (add-hook 'clojure-mode-hook #'clojure-test-mode))

(stante-after nrepl
  (--each stante-clojure-common-modes
    (add-hook 'nrepl-mode-hook it))

  (add-hook 'nrepl-interaction-mode-hook #'nrepl-turn-on-eldoc-mode))


;;;; Python

(stante-after python
  (--each '(stante-python-filling subword-mode)
    (add-hook 'python-mode-hook it))

  ;; Fill according to PEP 8
  (defun stante-python-filling ()
    "Configure filling for Python."
    ;; PEP 8 recommends a maximum of 79 characters
    (setq fill-column 79))

  ;; Use a decent syntax and style checker
  (setq python-check-command "flake8"))


;;;; Shell scripting

;; Teach Emacs about Zsh scripts
(stante-auto-modes 'sh-mode "\\.zsh\\'")

;; Shell script indentation styles
(stante-after sh-script
  (setq sh-styles-alist
        '(("zsh"
           (sh-basic-offset . 2)
           (sh-first-lines-indent . 0)
           (sh-indent-after-case . +)
           (sh-indent-after-do . +)
           (sh-indent-after-done . 0)
           (sh-indent-after-else . +)
           (sh-indent-after-if . +)
           (sh-indent-after-loop-construct . +)
           (sh-indent-after-open . +)
           (sh-indent-comment)
           (sh-indent-for-case-alt . ++)
           (sh-indent-for-case-label . +)
           (sh-indent-for-continuation . +)
           (sh-indent-for-do . 0)
           (sh-indent-for-done . 0)
           (sh-indent-for-else . 0)
           (sh-indent-for-fi . 0)
           (sh-indent-for-then . 0))))

  (add-hook 'sh-mode-hook (apply-partially #'sh-load-style "zsh")))


;;;; Misc programming languages

;; Coffeescript: Indentation
(stante-after coffee-mode
  (setq coffee-tab-width 2))

;; Haskell: Indentation, and some helpful modes
(stante-after haskell-mode
  (--each '(subword-mode
            turn-on-haskell-indentation
            turn-on-haskell-doc-mode
            turn-on-haskell-decl-scan)
    (add-hook 'haskell-mode-hook it)))

;; Ruby:  Handle Rakefiles
(stante-auto-modes 'ruby-mode "/Rakefile\\'")

;; SCSS: Don't compile when saving (aka please don't spam my directories!)
(stante-after scss-mode
  (setq scss-compile-at-save nil))

;; XML: Complete closing tags, and insert XML declarations into empty files
(stante-after nxml-mode
  (setq nxml-slash-auto-complete-flag t
        nxml-auto-insert-xml-declaration-flag t))

;; PKGBUILD: Recognize PKGBUILD's
(stante-auto-modes 'pkgbuild-mode "/PKGBUILD\\'")


;;;; Proof General

(load (expand-file-name "ProofGeneral/generic/proof-site.el" stante-vendor-dir))

;; On OS X, add executables from the Isabelle application bundle to path
(when (eq system-type 'darwin)
  (-when-let* ((bundle-dir (stante-path-of-bundle "de.tum.in.isabelle"))
               (bin-dir (expand-file-name "Contents/Resources/Isabelle/bin"
                                          bundle-dir)))
    (add-to-list 'exec-path bin-dir)))

;; Fix Isabelle string faces
(stante-after isar-syntax
  (set-face-attribute 'isabelle-string-face nil
                      :foreground nil :background nil
                      :inherit 'font-lock-string-face)
  (set-face-attribute 'isabelle-quote-face nil
                      :foreground nil :background nil
                      :inherit 'font-lock-string-face))


;;;; Git support

;; The one and only Git frontend
(stante-after magit
  (setq magit-save-some-buffers 'dontask ; Don't ask for saving
        magit-set-upstream-on-push t))   ; Ask for setting upstream branch on push

;; Show Git diff state in Fringe
(stante-after git-gutter
  (diminish 'git-gutter-mode)
  (require 'git-gutter-fringe))
(global-git-gutter-mode)

(stante-after gist
  (setq gist-view-gist t))              ; View Gists in browser after creation


;;;; Tools and utilities

;; Powerful search and narrowing framework
(require 'helm-config)
(unbind-key helm-command-prefix-key)
(setq helm-command-prefix-key "C-c c")

;; Project interaction
(stante-after projectile (diminish 'projectile-mode))
(projectile-global-mode)

;; Quickly switch to IELM
(defun stante-switch-to-ielm ()
  "Switch to an ielm window.

Create a new ielm process if required."
  (interactive)
  (pop-to-buffer (get-buffer-create "*ielm*"))
  (ielm))

;; Searching with Ack (the aliases are for fullack compatibility)
(defalias 'ack 'ack-and-a-half)
(defalias 'ack-same 'ack-and-a-half-same)
(defalias 'ack-find-file 'ack-and-a-half-find-file)
(defalias 'ack-find-file-same 'ack-and-a-half-find-file-same)

;; Google from Emacs, under C-c /
(google-this-mode)
(stante-after google-this (diminish 'google-this-mode))


;;;; Personal organization

;; In Europe, the week starts on Monday
(stante-after calendar
  (setq calendar-week-start-day 1))


;;;; Org mode

;; Tell Org where our files are located.  We keep them in Dropbox for easy
;; synchronization.
(stante-after org
  (setq org-directory (expand-file-name "~/Dropbox/Org")
        org-agenda-files (list org-directory)
        org-default-notes-file (expand-file-name "notes.org" org-directory)
        org-completion-use-ido t        ; Complete with IDO in Org
        org-yank-adjusted-subtrees t)   ; Adjust level when yanking entire trees

  (make-directory org-directory :with-parents)

  ;; Plug windmove into Org
  (add-hook 'org-shiftup-final-hook 'windmove-up)
  (add-hook 'org-shiftleft-final-hook 'windmove-left)
  (add-hook 'org-shiftdown-final-hook 'windmove-down)
  (add-hook 'org-shiftright-final-hook 'windmove-right)

  ;; Disable long lines highlighting in Org.  Org changes the visual appearance
  ;; of buffer text (e.g. link collapsing), thus text may appear shorter than
  ;; the fill column while it is not.  The whitespace mode highlighting is very
  ;; irritating in such cases.
  (stante-after whitespace
    (add-hook 'org-mode-hook #'stante-whitespace-style-no-long-lines))

  ;; Teach Electric about Org mode pairs
  (defun stante-org-electric-pairs ()
    (stante-add-local-electric-pairs '((?* . ?*)
                                       (?/ . ?/)
                                       (?= . ?=)
                                       (?~ . ?~))))
  (add-hook 'org-mode-hook #'stante-org-electric-pairs))

;; Configure Org mobile target folder and inbox.  Again, we use Dropbox to get
;; synchronization for free.
(stante-after org-mobile
  (setq org-mobile-directory "~/Dropbox/Org/Mobile"
        org-mobile-inbox-for-pull
        (expand-file-name "from-mobile.org" org-directory))

  (make-directory org-mobile-directory :with-parents))


;; Key bindings

;; Improve standard bindings
(bind-key "M-x" #'smex)
(bind-key "C-x C-b" #'ibuffer)
(bind-key "C-S-<backspace>" #'stante-smart-kill-whole-line)
(bind-key "C-a" #'stante-back-to-indentation-or-beginning-of-line)
(bind-key "M-/" #'hippie-expand)
;; Complement standard bindings (the comments indicate the related bindings)
(bind-key "M-X" #'smex-major-mode-commands)                  ; M-x
(bind-key "C-<backspace>" #'stante-smart-backward-kill-line) ; C-S-backspace
(bind-key "C-S-j" #'stante-smart-open-line)                  ; C-j
(bind-key "M-Z" #'zap-up-to-char)                            ; M-z
(bind-key "C-h A" #'apropos)                                 ; C-h a
(bind-key "C-x p" #'proced)                                  ; C-x p
;; Find definition sources fast
(bind-key "C-h F" #'find-function)                           ; C-h f
(bind-key "C-h V" #'find-variable)                           ; C-h v
;; Describe all user key bindings
(bind-key "C-h K" #'describe-personal-keybindings)

;; Key bindings for extension packages
(bind-key "C-=" #'er/expand-region)
(bind-key "C-c SPC" #'ace-jump-mode)
(bind-key "C-c C-SPC" #'ace-jump-mode)
(bind-key "C-x SPC" #'ace-jump-mode-pop-mark)

;; User key bindings in the C-c space.
(bind-key "C-c A" #'org-agenda)
;; Ack bindings
(bind-key "C-c a a" #'ack-and-a-half)
(bind-key "C-c a s" #'ack-and-a-half-same)
(bind-key "C-c b" #'stante-switch-to-previous-buffer)
(bind-key "C-c C" #'org-capture)
;; Helm bindings
(bind-key "C-c c /" #'helm-find)
(bind-key "C-c c 8" #'helm-ucs)
(bind-key "C-c c <tab>" #'helm-lisp-completion-at-point)
(bind-key "C-c c A" #'helm-apropos)
(bind-key "C-c c C-," #'helm-calcul-expression)
(bind-key "C-c c C-:" #'helm-eval-expression-with-eldoc)
(bind-key "C-c c C-c <SPC>" #'helm-all-mark-rings)
(bind-key "C-c c C-c C-b" #'helm-browse-code)
(bind-key "C-c c C-c C-x" #'helm-run-external-command)
(bind-key "C-c c C-c f" #'helm-recentf)
(bind-key "C-c c C-c g" #'helm-google-suggest)
(bind-key "C-c c C-x C-b" #'helm-buffers-list)
(bind-key "C-c c C-x C-f" #'helm-find-files)
(bind-key "C-c c C-x r b" #'helm-bookmarks)
(bind-key "C-c c C-x r i" #'helm-register)
(bind-key "C-c c M-g s" #'helm-do-grep)
(bind-key "C-c c M-s o" #'helm-occur)
(bind-key "C-c c M-x" #'helm-M-x)
(bind-key "C-c c M-y" #'helm-show-kill-ring)
(bind-key "C-c c P" #'helm-list-emacs-process)
(bind-key "C-c c a" #'helm-ack)
(bind-key "C-c c b" #'helm-resume)
(bind-key "C-c c c" #'helm-colors)
(bind-key "C-c c e" #'helm-etags-select)
(bind-key "C-c c f" #'helm-for-files)
(bind-key "C-c c g" #'helm-do-grep)
(bind-key "C-c c h g" #'helm-info-gnus)
(bind-key "C-c c h i" #'helm-info-at-point)
(bind-key "C-c c h r" #'helm-info-emacs)
(bind-key "C-c c i" #'helm-imenu)
(bind-key "C-c c l" #'helm-locate)
(bind-key "C-c c m" #'helm-man-woman)
(bind-key "C-c c o" #'helm-occur)
(bind-key "C-c c p" #'helm-projectile)
(bind-key "C-c c r" #'helm-regexp)
(bind-key "C-c c s" #'helm-surfraw)
(bind-key "C-c c t" #'helm-top)
;; File commands
(bind-key "C-c f r" #'stante-ido-find-recentf)
(bind-key "C-c f o" #'stante-open-with)
(bind-key "C-c f R" #'stante-rename-file-and-buffer)
(bind-key "C-c f D" #'stante-delete-file-and-buffer)
(bind-key "C-c f w" #'stante-copy-filename-as-kill)
(bind-key "C-c f i" #'stante-find-user-init-file-other-window)
;; Gist commands
(bind-key "C-c G c" #'gist-region-or-buffer)
(bind-key "C-c G l" #'gist-list)
(bind-key "C-c g" #'magit-status)
(bind-key "C-c i" #'imenu)
;; Multiple Cursors
(bind-key "C-c m l" #'mc/edit-lines)
(bind-key "C-c m C-a" #'mc/edit-beginnings-of-lines)
(bind-key "C-c m C-e" #'mc/edit-ends-of-lines)
(bind-key "C-c m C-s" #'mc/mark-all-in-region)
(bind-key "C-c m >" #'mc/mark-next-like-this)
(bind-key "C-c m <" #'mc/mark-previous-like-this)
(bind-key "C-c m e" #'mc/mark-more-like-this-extended)
(bind-key "C-c m h" #'mc/mark-all-like-this-dwim)
(bind-key "C-c o" #'occur)
;; Symbol operations
(bind-key "C-c s o" #'highlight-symbol-occur)
(bind-key "C-c s %" #'highlight-symbol-query-replace)
(bind-key "C-c s n" #'highlight-symbol-next-in-defun)
(bind-key "C-c s p" #'highlight-symbol-prev-in-defun)
(bind-key "C-c s M-n" #'highlight-symbol-next)
(bind-key "C-c s M-p" #'highlight-symbol-prev)
(bind-key "C-c z" #'stante-switch-to-ielm)

(stante-after lisp-mode
  (bind-key "C-c e" #'macrostep-expand emacs-lisp-mode-map))

;; Local Variables:
;; coding: utf-8
;; End:

;;; init.el ends here
