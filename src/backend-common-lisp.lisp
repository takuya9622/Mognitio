(in-package #:mognitio.backend.cl)

(defstruct (compiled-program
             (:constructor %make-compiled-program
                 (function span &optional warnings-p compiler-output)))
  (function nil :read-only t) (span nil :read-only t)
  (warnings-p nil :read-only t) (compiler-output "" :read-only t))

(defun expression-form (node checked names)
  (labels ((form (child) (expression-form child checked names))
           (symbol-for (child)
             (or (gethash (local-symbol-id (checked-symbol checked child)) names)
                 (internal-error "Missing host binding")))
           (sequence-form (statements tail index)
             (if (= index (length statements)) (form tail)
                 (let ((statement (aref statements index)))
                   (etypecase statement
                     (local-binding
                      (list 'cl:let
                            (list (list (symbol-for statement) (form (local-binding-initializer statement))))
                            (sequence-form statements tail (1+ index))))
                     (assignment
                      (list 'cl:progn (list 'cl:setq (symbol-for statement) (form (assignment-rhs statement)))
                            (sequence-form statements tail (1+ index)))))))))
    (typecase node
      (boolean-literal (ecase (boolean-literal-value node) (:true t) (:false nil)))
      (integer-literal (checked-literal checked node))
      (variable-reference (symbol-for node))
      (sequence-node (sequence-form (sequence-node-statements node) (sequence-node-tail node) 0))
      (grouping (form (grouping-expression node)))
      (if-expression
       (list 'cl:if (form (if-expression-condition node))
                   (form (if-expression-then-branch node)) (form (if-expression-else-branch node))))
      (unary-expression
       (if (checked-literal-p checked node) (checked-literal checked node)
           (list 'mognitio.integer:checked-arithmetic :neg (form (unary-expression-operand node)))))
      (binary-expression
       (let* ((a (make-symbol "LEFT")) (b (make-symbol "RIGHT"))
              (op (token-kind (binary-expression-operator node)))
              (body
                (if (member op '(:add :sub :mul :div :rem))
                    (list 'mognitio.integer:checked-arithmetic op a b)
                    (let ((comparison
                            (list (case op
                                    ((:eq :ne) (if (eq (checked-type checked (binary-expression-left node)) :bool)
                                                   'cl:eq 'cl:=))
                                    (:lt 'cl:<) (:le 'cl:<=) (:gt 'cl:>) (:ge 'cl:>=))
                                  a b)))
                      (if (eq op :ne) (list 'cl:not comparison) comparison)))))
         (list 'cl:let* (list (list a (form (binary-expression-left node)))
                              (list b (form (binary-expression-right node)))) body)))
      (t (internal-error "Invalid checked AST")))))

(defun program-form (checked)
  (let ((names (make-hash-table)) (program (checked-program-program checked)))
    (loop for symbol across (checked-program-bindings checked)
          do (setf (gethash (local-symbol-id symbol) names) (make-symbol "LOCAL")))
    (expression-form (make-sequence-node :statements (program-statements program)
                                         :tail (program-root program))
                     checked names)))

(defun host-compile (form)
  (with-compilation-unit (:override t)
    (compile nil form)))

(defun call-isolated (span thunk &optional runtime-allowed)
  (let* ((capture (make-string-output-stream))
         (*standard-output* capture) (*error-output* capture) (*trace-output* capture)
         (*compile-verbose* nil) (*compile-print* nil))
    (handler-case (with-compilation-unit (:override t) (funcall thunk))
      (mognitio.runtime:integer-runtime-failure (condition)
        (if runtime-allowed (error condition)
            (internal-error "Arithmetic evaluated during host compilation")))
      (compiler-failure (condition) (error condition))
      (error ()
        (fail-at span :internal "Host compilation or execution failed" 'internal-failure)))))

(defun compile-program (checked)
  (unless (typep checked 'checked-program)
    (internal-error "Backend requires CheckedProgram"))
  (let* ((root (program-root (checked-program-program checked)))
         (span (node-span root)))
    (call-isolated
     span
     (lambda ()
       (multiple-value-bind (function warnings-p failure-p)
           (host-compile (list 'cl:lambda '() (program-form checked)))
         (when (or failure-p (not (compiled-function-p function)))
           (fail-at span :internal "Host compile did not produce a valid function"
                    'internal-failure))
         (%make-compiled-program function span warnings-p
                                 (get-output-stream-string *standard-output*)))))))

(defun execute-program (compiled)
  (unless (typep compiled 'compiled-program)
    (internal-error "Expected CompiledProgram"))
  (call-isolated
   (compiled-program-span compiled)
   (lambda ()
     (let ((result (funcall (compiled-program-function compiled))))
       (cond ((eq result t) :true)
             ((eq result nil) :false)
             (t (fail-at (compiled-program-span compiled) :internal
                         "Host returned a non-boolean result" 'internal-failure))))) t))
