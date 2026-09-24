(in-package #:mognitio.syntax)

;; Type syntax retains token compatibility for the non-generic readers.
(defstruct try-expression operand span)
(defstruct panic-expression block span)

(defun error-node-span (node)
  (typecase node
    (try-expression (try-expression-span node))
    (panic-expression (panic-expression-span node))))
