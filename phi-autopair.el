(if (not (locate-library "paredit"))
    (error "Cannot open load file: paredit.el")
  (autoload 'paredit-backward-delete "paredit")
  (autoload 'paredit-forward-delete "paredit")
  (autoload 'paredit-splice-sexp-killing-backward "paredit")
  (autoload 'paredit-splice-sexp-killing-forward "paredit"))

;; + customs

(defvar phi-autopair-lispy-modes
  '(lisp-mode emacs-lisp-mode
              scheme-mode lisp-interaction-mode))

(defvar phi-autopair-delete-hungry t)

;; + internal vars

(defvar phi-autopair-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap delete-char] 'phi-autopair-delete-forward)
    (define-key map [remap hungry-delete] 'phi-autopair-delete-forward)
    (define-key map [remap delete-backward-char] 'phi-autopair-delete-backward)
    (define-key map [remap backward-delete-char] 'phi-autopair-delete-backward)
    (define-key map [remap backward-delete-char-untabify] 'phi-autopair-delete-backward)
    (define-key map [remap backward-kill-word] 'phi-autopair-delete-backward-word)
    (define-key map [remap kill-word] 'phi-autopair-delete-forward-word)
    map))

(defvar phi-autopair--pairs nil)
(make-variable-buffer-local 'phi-autopair--pairs)

(defun phi-autopair--setup ()
  (let ((lst nil)
        (table (syntax-table))
        (open (car (string-to-syntax "(")))
        (paired (car (string-to-syntax "$")))
        (string (car (string-to-syntax "\""))))
    (map-char-table
     (lambda (char entry)
       (let ((class (syntax-class entry)))
         (cond ((eq class paired)
                (add-to-list 'lst `(,char pair . ,(char-to-string char)))
                (define-key phi-autopair-mode-map
                  (char-to-string char) 'phi-autopair-command))
               ((eq class open)
                (add-to-list 'lst `(,char pair . ,(char-to-string (cdr entry))))
                (define-key phi-autopair-mode-map
                  (char-to-string char) 'phi-autopair-command))
               ((eq class string)
                (add-to-list 'lst `(,char string . ,(char-to-string char)))
                (define-key phi-autopair-mode-map
                  (char-to-string char) 'phi-autopair-command)))))
     (syntax-table))
    (setq phi-autopair--pairs lst)))

;; + minor-mode

(define-minor-mode phi-autopair-mode
  "autopair mode without post/pre-command-hook"
  :init-value nil
  :keymap phi-autopair-mode-map
  (if phi-autopair-mode
      (progn
        (add-hook 'after-change-major-mode-hook 'phi-autopair--setup nil t)
        (phi-autopair--setup))
    (remove-hook 'after-change-major-mode-hook 'phi-autopair--setup t)))

(define-globalized-minor-mode phi-autopair-global-mode
  phi-autopair-mode
  (lambda () (phi-autopair-mode 1)))

;; + insert command

(defun phi-autopair-command ()
  (interactive)
  (let* ((open (char-to-string last-command-event))
         (pair (cdr (assoc last-command-event phi-autopair--pairs))))
    (if (or (looking-back "\\\\") (null pair))
        ;; if escaped, just insert it
        (insert open)
      (let ((type (car pair)) (close (cdr pair)))
        ;; escape string delimiters in string
        (when (and (nth 3 (syntax-ppss)) (eq type 'string))
          (setq open (concat "\\" open)
                close (concat "\\" close)))
        (if (use-region-p)
            ;; wrap
            (let ((beg (min (region-beginning) (region-end)))
                  (end (max (region-beginning) (region-end))))
              (deactivate-mark)
              (goto-char end)
              (insert close)
              (goto-char beg)
              (insert open))
          ;; add spaces around parens in lispy-mode(s)
          (when (and (not (nth 3 (syntax-ppss)))
                     (member major-mode phi-autopair-lispy-modes))
            (setq open (concat
                        (unless (looking-back "[\s\t\n]\\|\\s(\\|^\\|\\s'") " ")
                        open)
                  close (concat
                         close
                         (unless (looking-at "[\s\t\n]\\|\\s)\\|$") " "))))
          ;; insert
          (insert open)
          (save-excursion (insert close)))))))

;; + delete commands

(defun phi-autopair-delete-backward (&optional strict)
  (interactive)
  (let ((syntax-ppss (syntax-ppss)))
    (cond ((and (not (nth 3 syntax-ppss))
                (not (nth 4 syntax-ppss))
                (looking-back "\\s("))
           (condition-case err
               (paredit-splice-sexp-killing-backward)
             (error (unless strict (backward-delete-char 1)))))
          ((and phi-autopair-delete-hungry
                (looking-back "[\s\t]"))
           (delete-region
            (point)
            (progn (skip-chars-backward "\s\t") (point))))
          (strict
           (paredit-backward-delete))
          (t
           (delete-char -1)))))

(defun phi-autopair-delete-forward (&optional strict)
  (interactive)
  (let ((syntax-ppss (syntax-ppss)))
    (cond ((and (not (nth 3 syntax-ppss))
                (not (nth 4 syntax-ppss))
                (looking-at "\\s)"))
           (condition-case err
               (paredit-splice-sexp-killing-forward)
             (error (unless strict (delete-char 1)))))
          ((and phi-autopair-delete-hungry
                (looking-at "[\s\t\n]"))
           (delete-region
            (point)
            (progn (skip-chars-forward "\s\t\n") (point))))
          (strict
           (paredit-forward-delete))
          (t
           (delete-char 1)))))

(defun phi-autopair-delete-backward-word ()
  (interactive)
  (while (progn
           (phi-autopair-delete-backward 'strict)
           (not (looking-back "\\<."))))
  (delete-char -1))

(defun phi-autopair-delete-forward-word ()
  (interactive)
  (while (progn
           (phi-autopair-delete-forward 'strict)
           (not (looking-at ".\\>"))))
  (delete-char 1))

(eval-after-load "delsel"
  '(dolist (symbol '(phi-autopair-delete-backward
                     phi-autopair-delete-forward
                     phi-autopair-delete-backward-word
                     phi-autopair-delete-forward-word))
     (put symbol 'delete-selection t)))

;; + provide

(provide 'phi-autopair)