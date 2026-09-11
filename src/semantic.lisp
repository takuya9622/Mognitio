(in-package #:mognitio.semantic)

(defstruct (checked-program (:constructor %make-checked-program (program)))
  (program nil :read-only t))

(defun check-expression (node)
  (typecase node
    (boolean-literal
     (unless (member (boolean-literal-value node) '(:true :false))
       (fail-at (boolean-literal-span node) :internal
                "Invalid boolean literal" 'internal-failure)))
    (if-expression
     (dolist (child (list (if-expression-condition node)
                         (if-expression-then-branch node)
                         (if-expression-else-branch node)))
       (unless (eq (check-expression child) :bool)
         (internal-error "Invalid semantic result"))))
    (t (internal-error "Invalid AST node or missing child")))
  :bool)

(defun check-program (program)
  (unless (typep program 'program) (internal-error "Expected Program"))
  (check-expression (program-root program))
  (%make-checked-program program))
