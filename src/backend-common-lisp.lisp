(in-package #:mognitio.backend.cl)

(defstruct (compiled-program
             (:constructor %make-compiled-program
                 (function span &optional warnings-p compiler-output)))
  (function nil :read-only t) (span nil :read-only t)
  (warnings-p nil :read-only t) (compiler-output "" :read-only t))

(defun expression-form (node)
  (typecase node
    (boolean-literal
     (case (boolean-literal-value node)
       (:true t) (:false nil)
       (otherwise (internal-error "Invalid checked literal"))))
    (if-expression
     (list 'cl:if (expression-form (if-expression-condition node))
                  (expression-form (if-expression-then-branch node))
                  (expression-form (if-expression-else-branch node))))
    (t (internal-error "Invalid checked AST"))))

(defun host-compile (form)
  (with-compilation-unit (:override t)
    (compile nil form)))

(defun call-isolated (span thunk)
  (let* ((capture (make-string-output-stream))
         (*standard-output* capture) (*error-output* capture) (*trace-output* capture)
         (*compile-verbose* nil) (*compile-print* nil))
    (handler-case (with-compilation-unit (:override t) (funcall thunk))
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
           (host-compile (list 'cl:lambda '() (expression-form root)))
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
                         "Host returned a non-boolean result" 'internal-failure)))))))
