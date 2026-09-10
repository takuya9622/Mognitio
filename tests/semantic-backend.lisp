(in-package #:mognitio.tests)

(deftest v13-semantic-whole-tree
  (let* ((program (parse-text "if(true){false}else{true}"))
         (root (program-root program))
         (checked (check-program program))
         (visited nil)
         (original (fdefinition 'mognitio.semantic::check-expression)))
    (same program (checked-program-program checked))
    (replacing (mognitio.semantic::check-expression
                (lambda (node) (push node visited) (funcall original node)))
      (check-program program))
    (same (list root (if-expression-condition root)
                     (if-expression-then-branch root)
                     (if-expression-else-branch root))
          (reverse visited))
    (dolist (bad (list nil 17
                      (make-boolean-literal :value :invalid :span (node-span root))))
      (signals internal-failure (check-program (make-program :source (program-source program)
                                                             :root bad)))
      (signals internal-failure
        (check-program
         (make-program :source (program-source program)
                       :root (make-if-expression :condition (if-expression-condition root)
                                                 :then-branch (if-expression-then-branch root)
                                                 :else-branch bad :span (node-span root))))))))

(deftest v14-checked-boundary-and-forms
  (signals internal-failure (compile-program (parse-text "true")))
  (dolist (case '(("true" (lambda () t))
                  ("false" (lambda () nil))
                  ("if(if(false){true}else{false}){false}else{true}"
                   (lambda () (if (if nil t nil) nil t)))))
    (let ((original (fdefinition 'mognitio.backend.cl::host-compile))
          (seen nil))
      (replacing (mognitio.backend.cl::host-compile
                  (lambda (form) (setf seen form) (funcall original form)))
        (compile-program (check-program (parse-text (first case)))))
      (same (second case) seen))))

(deftest v15-host-compile-contract
  (let ((checked (check-program (parse-text "true"))))
    (dolist (replacement (list (lambda (form) (declare (ignore form)) (values #'identity nil t))
                              (lambda (form) (declare (ignore form)) (error "Host fault"))
                              (lambda (form) (declare (ignore form)) (values 42 nil nil))))
      (replacing (mognitio.backend.cl::host-compile replacement)
        (signals internal-failure (compile-program checked))))
    (let ((original (fdefinition 'mognitio.backend.cl::host-compile)))
      (replacing (mognitio.backend.cl::host-compile
                  (lambda (form)
                    (format t "host stdout")
                    (format *error-output* "host stderr")
                    (format *trace-output* "host trace")
                    (values (funcall original form) t nil)))
        (let ((out (make-string-output-stream)) (err (make-string-output-stream)))
          (let ((*standard-output* out) (*error-output* err) (*trace-output* err))
            (same :true (execute-program (compile-program checked))))
          (same "" (get-output-stream-string out))
          (same "" (get-output-stream-string err)))))))

(deftest v16-results-and-if-evaluation
  (let ((span (node-span (program-root (parse-text "true")))))
    (dolist (case '((t :true) (nil :false)))
      (same (second case)
            (execute-program
             (mognitio.backend.cl::%make-compiled-program
              (compile nil (list 'lambda '() (first case))) span))))
    (signals internal-failure
      (execute-program (mognitio.backend.cl::%make-compiled-program
                        (compile nil '(lambda () 7)) span)))
    (signals internal-failure
      (execute-program (mognitio.backend.cl::%make-compiled-program
                        (compile nil '(lambda () (error "execution fault"))) span))))
  ;; Observe CL:IF directly with test-only effects; production forms are checked in V14.
  (dolist (condition '(t nil))
    (let ((function
            (compile nil
                     `(lambda ()
                         (let ((visits nil))
                           (if (progn (push :condition visits) ,condition)
                               (push :then visits)
                               (push :else visits))
                           (reverse visits))))))
      (same (list :condition (if condition :then :else)) (funcall function)))))

(deftest backend-execution-output-isolation
  (let* ((span (node-span (program-root (parse-text "true"))))
         (compiled (mognitio.backend.cl::%make-compiled-program
                    (compile nil '(lambda ()
                                    (format t "noise")
                                    (format *error-output* "noise")
                                    (format *trace-output* "noise")
                                    t)) span))
         (out (make-string-output-stream)) (err (make-string-output-stream)))
    (let ((*standard-output* out) (*error-output* err) (*trace-output* err))
      (same :true (execute-program compiled)))
    (same "" (get-output-stream-string out))
    (same "" (get-output-stream-string err))))

(deftest host-warning-metadata-and-failed-compile-stops
  (let* ((original (fdefinition 'mognitio.backend.cl::host-compile))
         (checked (check-program (parse-text "true"))))
    (replacing (mognitio.backend.cl::host-compile
                (lambda (form)
                  (format *error-output* "captured warning")
                  (values (funcall original form) t nil)))
      (let ((compiled (compile-program checked)))
        (is (mognitio.backend.cl::compiled-program-warnings-p compiled))
        (is (search "captured warning"
                    (mognitio.backend.cl::compiled-program-compiler-output compiled))))))
  (let ((path (put-text (fresh-path) "true")) (executions 0))
    (replacing (mognitio.backend.cl::host-compile
                (lambda (form) (declare (ignore form))
                  (values (compile nil '(lambda () t)) nil t)))
      (replacing (mognitio.backend.cl:execute-program
                  (lambda (compiled) (declare (ignore compiled)) (incf executions) :true))
        (multiple-value-bind (out err code)
            (driver-result (list "run" (namestring path)))
          (same 3 code) (same "" out) (is (search "internal:" err)))))
    (same 0 executions)))
