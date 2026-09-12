(in-package #:mognitio.tests)

(deftest v17-arguments-and-io
  (dolist (args '(nil ("run") ("run" "") ("build" "x.mgn") ("repl")
                  ("run" "x" "y") ("--help")))
    (expect-cli args 2))
  (expect-cli (list "run" (namestring (fresh-path))) 2)
  (expect-cli (list "run" (namestring *temp*)) 2)
  (let ((path (put-text (fresh-path) "true")))
    (is (not (zerop (sb-posix:getuid))) "Permission test requires non-root")
    (unwind-protect
         (progn (sb-posix:chmod (namestring path) 0)
                (expect-cli (list "run" (namestring path)) 2))
      (sb-posix:chmod (namestring path) #o600))))

(defun with-phase-failure (failure-index condition thunk)
  (let* ((names '(mognitio.source:read-source mognitio.frontend:lex-source
                   mognitio.frontend:parse-program mognitio.semantic:check-program
                   mognitio.backend.cl:compile-program mognitio.backend.cl:execute-program))
         (saved (mapcar #'fdefinition names))
         (calls nil))
    (labels ((wrapper (index original)
               (lambda (&rest args)
                 (push index calls)
                 (if (= index failure-index) (error condition)
                     (apply original args)))))
      (unwind-protect
           (progn
             (loop for name in names for original in saved for index from 0
                   do (setf (fdefinition name) (wrapper index original)))
             (funcall thunk)
             (same (loop for index from 0 to failure-index collect index)
                   (reverse calls)))
        (loop for name in names for original in saved
              do (setf (fdefinition name) original))))))

(deftest v18-driver-stops-after-failure
  (let ((path (put-text (fresh-path) "true")))
    (loop for phase in '(:source :lex :parse :semantic)
          for index from 0
          do (with-phase-failure
              index
              (make-condition 'source-failure
                              :diagnostic (make-diagnostic :phase phase :message "Injected"
                                                           :path (namestring path)
                                                           :line 1 :column 1))
              (lambda ()
                (multiple-value-bind (out err code)
                    (driver-result (list "run" (namestring path)))
                  (same 1 code) (same "" out)
                  (is (search (format nil ":1:1: ~(~A~):" phase) err))))))
    (with-phase-failure
     0 (make-condition 'usage-or-io-failure
                       :diagnostic (make-diagnostic :message "I/O fault"))
     (lambda ()
       (multiple-value-bind (out err code) (driver-result (list "run" (namestring path)))
         (declare (ignore err)) (same "" out) (same 2 code))))
    (loop for index in '(4 5)
          do (with-phase-failure
              index (make-condition 'simple-error :format-control "Unexpected host error")
              (lambda ()
                (multiple-value-bind (out err code)
                    (driver-result (list "run" (namestring path)))
                  (same 3 code) (same "" out) (is (search "internal:" err))))))))

(deftest invalid-source-never-compiles
  (dolist (case '((#(255) "source") (#(64) "lex")
                  (#(116 114 117 101 32 102 97 108 115 101) "parse")))
    (let ((path (put-bytes (fresh-path) (first case))) (calls 0))
      (replacing (mognitio.backend.cl::host-compile
                  (lambda (form) (declare (ignore form)) (incf calls) (error "Not reached")))
        (multiple-value-bind (out err code) (driver-result (list "run" (namestring path)))
          (same 1 code) (same "" out) (is (search (second case) err))))
      (same 0 calls))))

(defun fault-main ()
  ;; This entry exists only in the test system and never runs the test suite.
  (let* ((args (uiop:command-line-arguments))
         (mode (first args)) (path (second args)))
    (flet ((run () (mognitio.driver:run-cli (list "run" path)
                                           *standard-output* *error-output*)))
      (sb-ext:exit
       :code
       (cond
         ((string= mode "semantic")
          (replacing (mognitio.semantic:check-program
                      (lambda (program)
                        (fail-at (node-span (program-root program)) :semantic "Injected")))
            (run)))
         ((string= mode "codegen")
          (replacing (mognitio.backend.cl::expression-form
                      (lambda (node) (declare (ignore node)) (error "Injected codegen")))
            (run)))
         ((string= mode "compile-signal")
          (replacing (mognitio.backend.cl::host-compile
                      (lambda (form) (declare (ignore form)) (error "Injected compile")))
            (run)))
         ((string= mode "compile-failure")
          (replacing (mognitio.backend.cl::host-compile
                      (lambda (form) (declare (ignore form))
                        (values (compile nil '(lambda () (error "Must not execute"))) nil t)))
            (run)))
         ((string= mode "not-compiled")
          (replacing (mognitio.backend.cl::host-compile
                      (lambda (form) (declare (ignore form)) (values 42 nil nil)))
            (run)))
         ((string= mode "result")
          (replacing (mognitio.backend.cl::host-compile
                      (lambda (form) (declare (ignore form))
                        (values (compile nil '(lambda () 42)) nil nil)))
            (run)))
         ((string= mode "execute")
          (replacing (mognitio.backend.cl::host-compile
                      (lambda (form) (declare (ignore form))
                        (values (compile nil '(lambda () (error "Injected execute"))) nil nil)))
            (run)))
         (t 99))))))

(deftest v18-v19-process-faults
  (let ((path (put-text (fresh-path) "true")))
    (dolist (mode '("semantic" "codegen" "compile-signal" "compile-failure"
                    "not-compiled" "result" "execute"))
      (multiple-value-bind (out err code)
          (process-result (list "sbcl" "--noinform" "--script"
                                (namestring (root-path "tests/fault-entry.lisp"))
                                mode (namestring path)))
        (same (if (string= mode "semantic") 1 3) code)
        (same "" out)
        (is (search (if (string= mode "semantic") ": semantic:" ": internal:") err))
        (same 1 (count #\Newline err)))))
  ;; Exercise the real bootstrap handler using its script in a temporary layout.
  (let* ((directory (merge-pathnames "bootstrap/" *temp*))
         (entry (merge-pathnames "scripts/cli-entry.lisp" directory))
         (asd (merge-pathnames "mognitio.asd" directory)))
    (ensure-directories-exist entry)
    (uiop:copy-file (root-path "scripts/cli-entry.lisp") entry)
    (dolist (broken-asd (list nil "(error \"Injected load failure\")"
                             "(no-such-bootstrap-package:missing)"))
      (when broken-asd (put-text asd broken-asd))
      (multiple-value-bind (out err code)
          (process-result (list "sbcl" "--noinform" "--script" (namestring entry)))
        (same 3 code) (same "" out)
        (same (format nil "mgn: internal: Compiler bootstrap failed~%") err)))))

(deftest v20-paths-cwd-and-caches
  (let ((other (merge-pathnames "different cwd/" *temp*)))
    (ensure-directories-exist other)
    (dolist (name '("space file.mgn" "日本語.mgn" "*.mgn" "file[1]?.mgn" "-.mgn"))
      (let ((path (merge-pathnames (sb-ext:parse-native-namestring name) other)))
        (put-text path "false")
        (expect-cli (list "run" name) 0 :output (format nil "false~%") :directory other)))
    (let* ((cache (merge-pathnames "empty-cache/" *temp*))
           (source (put-text (merge-pathnames "input.mgn" other) "true"))
           (command (list "env" (format nil "XDG_CACHE_HOME=~A" (namestring cache))
                          "ASDF_OUTPUT_TRANSLATIONS=" "CL_SOURCE_REGISTRY="
                          (namestring (root-path "bin/mgn")) "run" (namestring source))))
      (is (not (probe-file cache)))
      (dotimes (iteration 2)
        (declare (ignorable iteration))
        (multiple-value-bind (out err code) (process-result command :directory other)
          (same 0 code) (same (format nil "true~%") out) (same "" err)))
      (is (probe-file cache)))))

(deftest diagnostics-one-line-and-stream-failure
  (let* ((name (format nil "line~%break.mgn"))
         (path (merge-pathnames name *temp*)))
    (put-text path "@")
    (let ((err (expect-cli (list "run" (namestring path)) 1 :phase "lex")))
      (is (search "line\\nbreak.mgn" err))))
  (let ((out (make-string-output-stream)))
    (render-diagnostic (make-diagnostic :phase :internal :message (format nil "a~%b~Cc" #\Return))
                       out)
    (same (format nil "mgn: internal: a\\nb\\rc~%") (get-output-stream-string out)))
  (let ((path (put-text (fresh-path) "true"))
        (out (make-string-output-stream)) (err (make-string-output-stream)))
    (close out)
    (same 3 (mognitio.driver:run-cli (list "run" (namestring path)) out err))
    (is (search "internal:" (get-output-stream-string err)))
    (close err)
    (same 3 (mognitio.driver:run-cli nil out err))))

(deftest launcher-missing-sbcl-and-user-init
  (multiple-value-bind (out err code)
      (process-result (list "env" "PATH=/nonexistent"
                            (namestring (root-path "bin/mgn"))))
    (same 3 code) (same "" out)
    (same (format nil "mgn: internal: SBCL is required~%") err))
  (let ((home (merge-pathnames "isolated-home/" *temp*))
        (source (put-text (fresh-path) "true")))
    (ensure-directories-exist home)
    (put-text (merge-pathnames ".sbclrc" home) "(error \"User init must not load\")")
    (multiple-value-bind (out err code)
        (process-result (list "env" (format nil "HOME=~A" (namestring home))
                              (namestring (root-path "bin/mgn")) "run" (namestring source)))
      (same 0 code) (same (format nil "true~%") out) (same "" err))))

(deftest harness-enforces-child-timeout
  (signals simple-error
    (process-result (list "sbcl" "--noinform" "--non-interactive" "--eval" "(sleep 30)")
                    :timeout 0.1)))

(deftest io-errors-preserve-internal-failures
  (let ((path (put-text (fresh-path) "true")))
    (multiple-value-bind (out err code)
        (driver-result (list "run" (format nil "invalid~Cpath.mgn" (code-char 0))))
      (same 2 code) (same "" out) (same 1 (count #\Newline err)))
    (replacing (mognitio.source::decode-source
                (lambda (&rest args) (declare (ignore args)) (error "Decoder host failure")))
      (multiple-value-bind (out err code) (driver-result (list "run" (namestring path)))
        (same 3 code) (same "" out) (is (search "internal:" err))))))
