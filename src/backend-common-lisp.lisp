(in-package #:mognitio.backend.cl)

(defstruct (compiled-program
             (:constructor %make-compiled-program
                 (function span &optional warnings-p compiler-output)))
  (function nil :read-only t) (span nil :read-only t)
  (warnings-p nil :read-only t) (compiler-output "" :read-only t))

(defun expression-form (node checked names functions exits)
  (labels ((form (child) (expression-form child checked names functions exits))
           (symbol-for (child)
             (or (gethash (local-symbol-id (checked-symbol checked child)) names)
                 (internal-error "Missing host binding")))
           (ordered (children build)
             (let ((bindings nil) (args nil))
               (dolist (child children)
                 (unless (checked-normal-type checked child)
                   (return-from ordered (list 'cl:let* (nreverse bindings) (form child))))
                 (let ((name (make-symbol "ARG")))
                   (push (list name (form child)) bindings) (push name args)))
               (list 'cl:let* (nreverse bindings) (funcall build (nreverse args)))))
           (sequence-form (statements tail index)
             (if (= index (length statements)) (form tail)
                 (let* ((statement (aref statements index))
                        (rhs (etypecase statement
                               (local-binding (local-binding-initializer statement))
                               (assignment (assignment-rhs statement)))))
                   (unless (checked-normal-type checked rhs)
                     (return-from sequence-form (form rhs)))
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
      (sequence-node (sequence-form (sequence-node-statements node) (sequence-node-terminal node) 0))
      (grouping (form (grouping-expression node)))
      (return-statement
       (let ((value (return-statement-value node)))
         (if (checked-normal-type checked value)
             (list 'cl:return-from (gethash (checked-return checked node) exits) (form value))
             (form value))))
      (call-expression
       (ordered (coerce (call-expression-arguments node) 'list)
                (lambda (args) (cons (gethash (signature-id (checked-call checked node)) functions) args))))
      (if-expression
       (if (null (checked-normal-type checked (if-expression-condition node)))
           (form (if-expression-condition node))
           (list 'cl:if (form (if-expression-condition node))
                   (form (if-expression-then-branch node)) (form (if-expression-else-branch node)))))
      (unary-expression
       (if (checked-literal-p checked node) (checked-literal checked node)
           (if (checked-normal-type checked (unary-expression-operand node))
               (list 'mognitio.integer:checked-arithmetic :neg (form (unary-expression-operand node)))
               (form (unary-expression-operand node)))))
      (binary-expression
       (ordered (list (binary-expression-left node) (binary-expression-right node))
         (lambda (args)
           (let ((op (token-kind (binary-expression-operator node))))
             (if (member op '(:add :sub :mul :div :rem))
                 (list* 'mognitio.integer:checked-arithmetic op args)
                 (let ((comparison
                         (cons (case op
                                 ((:eq :ne) (if (eq (checked-normal-type checked (binary-expression-left node)) :bool)
                                                'cl:eq 'cl:=))
                                 (:lt 'cl:<) (:le 'cl:<=) (:gt 'cl:>) (:ge 'cl:>=)) args)))
                   (if (eq op :ne) (list 'cl:not comparison) comparison)))))))
      (t (internal-error "Invalid checked AST")))))

(defun program-form (checked)
  (let ((names (make-hash-table)) (functions (make-hash-table)) (exits (make-hash-table))
        (program (checked-program-program checked)))
    (loop for symbol across (checked-program-bindings checked)
          do (setf (gethash (local-symbol-id symbol) names) (make-symbol "LOCAL")))
    (loop for signature across (checked-program-signatures checked) do
      (setf (gethash (signature-id signature) functions) (make-symbol "FUNCTION")
            (gethash (signature-id signature) exits) (make-symbol "RETURN")))
    (let ((definitions
            (loop for signature across (checked-program-signatures checked)
                  for declaration = (signature-declaration signature) when declaration collect
              (list (gethash (signature-id signature) functions)
                    (map 'list (lambda (p) (gethash (local-symbol-id (checked-symbol checked p)) names))
                         (function-declaration-parameters declaration))
                    (list 'cl:block (gethash (signature-id signature) exits)
                          (expression-form (function-declaration-body declaration) checked names functions exits)))))
          (entry (expression-form (make-sequence-node :statements (program-statements program)
                                    :terminal (program-root program)) checked names functions exits)))
      (if definitions
          (list 'cl:labels definitions (list 'cl:declare (cons 'cl:notinline (mapcar #'first definitions))) entry)
          entry))))

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
  (verify-checked-program checked)
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
