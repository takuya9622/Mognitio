(in-package #:mognitio.syntax)

(defstruct token (kind nil :read-only t) (span nil :read-only t))
(defstruct boolean-literal (value nil :read-only t) (span nil :read-only t))
(defstruct if-expression
  (condition nil :read-only t) (then-branch nil :read-only t)
  (else-branch nil :read-only t) (span nil :read-only t))
(defstruct program (source nil :read-only t) (root nil :read-only t))
(defun node-span (node)
  (typecase node
    (boolean-literal (boolean-literal-span node))
    (if-expression (if-expression-span node))
    (t nil)))
