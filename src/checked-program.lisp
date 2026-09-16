(in-package #:mognitio.semantic)

(defun verify-checked-program-internal (checked)
  (unless (checked-program-p checked) (internal-error "Expected CheckedProgram"))
  (let* ((program (checked-program-program checked)) (signatures (checked-program-signatures checked))
         (bindings (checked-program-bindings checked)) (edges (make-hash-table)))
    (labels ((require-checked (condition message) (unless condition (internal-error message)))
             (symbol-for (node owner)
               (let ((symbol (checked-symbol checked node)))
                 (require-checked
                  (and (typep (local-symbol-id symbol) `(integer 0 ,(1- (length bindings))))
                       (eq symbol (aref bindings (local-symbol-id symbol)))
                       (= owner (local-symbol-owner symbol))) "Invalid binding owner")
                 symbol))
             (visit (node owner &optional consumed-allowed)
               (let ((completion (checked-completion checked node)))
                 (require-checked (member (completion-normal-type completion) '(nil :int :bool)) "Invalid normal type")
                 (require-checked (member (completion-may-return completion) '(nil t)) "Invalid return summary"))
               (when (gethash node (checked-program-consumed checked))
                 (require-checked (and consumed-allowed (typep node 'integer-literal)
                                       (null (checked-normal-type checked node))) "Invalid consumed literal"))
               (typecase node
                 (boolean-literal (require-checked (eq (checked-normal-type checked node) :bool) "Invalid bool summary"))
                 (integer-literal
                  (unless consumed-allowed
                    (require-checked (and (eq (checked-normal-type checked node) :int)
                                          (mognitio.integer:in-range-p (checked-literal checked node))) "Invalid literal table")))
                 ((or variable-reference parameter)
                  (let ((symbol (symbol-for node owner)))
                    (require-checked (eq (local-symbol-type symbol) (checked-normal-type checked node)) "Invalid binding summary")))
                 (local-binding
                  (let ((symbol (symbol-for node owner)) (child (local-binding-initializer node)))
                    (visit child owner)
                    (require-checked (eq (local-symbol-type symbol) (checked-normal-type checked child)) "Invalid initializer type")))
                 (assignment (symbol-for node owner) (visit (assignment-rhs node) owner))
                 (grouping (visit (grouping-expression node) owner))
                 (sequence-node
                  (map nil (lambda (s) (visit s owner)) (sequence-node-statements node))
                  (visit (sequence-node-terminal node) owner))
                 (unary-expression
                  (visit (unary-expression-operand node) owner
                         (and (checked-literal-p checked node)
                              (= (checked-literal checked node) mognitio.integer:+minimum+))))
                 (binary-expression (visit (binary-expression-left node) owner) (visit (binary-expression-right node) owner))
                 (if-expression
                  (visit (if-expression-condition node) owner) (visit (if-expression-then-branch node) owner)
                  (visit (if-expression-else-branch node) owner))
                 (return-statement
                  (require-checked (and (plusp owner) (= owner (checked-return checked node))
                                        (null (checked-normal-type checked node))) "Invalid return owner")
                  (visit (return-statement-value node) owner))
                 (call-expression
                  (let* ((signature (checked-call checked node)) (id (signature-id signature)))
                    (require-checked
                     (and (typep id `(integer 1 ,(1- (length signatures)))) (eq signature (aref signatures id))
                          (string= (token-text (call-expression-callee node))
                                   (token-text (function-declaration-name (signature-declaration signature))))
                          (= (length (call-expression-arguments node)) (length (signature-parameter-types signature))))
                     "Invalid resolved callee")
                    (push (cons id (node-span node)) (gethash owner edges)))
                  (map nil (lambda (arg) (visit arg owner)) (call-expression-arguments node)))
                 (t (internal-error "Invalid checked AST node")))))
      (require-checked (= (length signatures) (1+ (length (program-functions program)))) "Missing signatures")
      (loop for signature across signatures for id from 0 do
        (require-checked (and (= id (signature-id signature))
                              (member (signature-result-type signature) '(:bool :int))
                              (every (lambda (type) (member type '(:bool :int))) (signature-parameter-types signature)))
                         "Invalid checked signature")
        (if (zerop id)
            (require-checked (and (null (signature-declaration signature)) (null (signature-parameter-types signature))
                                  (eq (signature-result-type signature) :bool)) "Invalid checked entry")
            (require-checked (eq (signature-declaration signature) (aref (program-functions program) (1- id))) "Invalid declaration owner")))
      (loop for symbol across bindings for id from 0 do
        (require-checked (and (= id (local-symbol-id symbol))
                              (typep (local-symbol-owner symbol) `(integer 0 ,(1- (length signatures))))
                              (member (local-symbol-type symbol) '(:bool :int))
                              (member (local-symbol-mutability symbol) '(:let :var :parameter))) "Invalid checked binding"))
      (loop for signature across signatures for declaration = (signature-declaration signature) when declaration do
        (map nil (lambda (p) (visit p (signature-id signature))) (function-declaration-parameters declaration))
        (visit (function-declaration-body declaration) (signature-id signature)))
      (map nil (lambda (s) (visit s 0)) (program-statements program))
      (visit (program-root program) 0)
      (check-call-graph (loop for id below (length signatures) collect id) edges
                        (lambda (span) (declare (ignore span)) (internal-error "Cyclic checked calls")))))
  checked)

(defun verify-checked-program (checked)
  (handler-case (verify-checked-program-internal checked)
    (internal-failure (condition) (error condition))
    (error () (internal-error "Malformed CheckedProgram"))))
