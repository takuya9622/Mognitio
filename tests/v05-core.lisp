(in-package #:mognitio.tests)

(defun v05-loop-module ()
  (flet ((inst (id type op &key value operands)
           (mognitio.ir:make-instruction :result id :type type :op op :value value :operands operands)))
    (mognitio.ir:make-module :functions
      (list (mognitio.ir:make-ir-function :id 0 :result-type :bool :entry 0 :blocks
        (list
         (mognitio.ir:make-basic-block :id 0
           :instructions (list (inst 0 :int :constant :value 0)
                               (inst 1 :int :constant :value 3)
                               (inst 2 :int :constant :value 1)) :terminator '(:jump 1 (0)))
         (mognitio.ir:make-basic-block :id 1 :parameters '((3 . :int))
           :instructions (list (inst 4 :bool :lt :operands '(3 1))) :terminator '(:branch 4 2 3))
         (mognitio.ir:make-basic-block :id 2
           :instructions (list (inst 5 :int :add :operands '(3 2))) :terminator '(:jump 1 (5)))
         (mognitio.ir:make-basic-block :id 3
           :instructions (list (inst 6 :bool :eq :operands '(3 1))) :terminator '(:return 6))))))))

(deftest v05-cyclic-core-verifier
  (is (mognitio.ir:verify-module (v05-loop-module)))
  (let ((module (v05-loop-module)))
    ;; Header still dominates the exit if the backedge is listed before entry.
    (setf (mognitio.ir:ir-function-blocks (first (mognitio.ir:module-functions module)))
          (reverse (entry-blocks module)))
    (is (mognitio.ir:verify-module module)))
  (dolist (mutation
           (list (lambda (bs) (setf (mognitio.ir:basic-block-terminator (third bs)) '(:jump 1 (4))))
                 (lambda (bs) (setf (mognitio.ir:basic-block-terminator (third bs)) '(:jump 0 ())))
                 (lambda (bs) (setf (mognitio.ir:instruction-operands
                                     (first (mognitio.ir:basic-block-instructions (fourth bs)))) '(5 1)))
                 (lambda (bs) (setf (mognitio.ir:basic-block-terminator (third bs)) '(:jump 1 ())))))
    (let ((module (v05-loop-module)))
      (funcall mutation (entry-blocks module))
      (signals internal-failure (mognitio.ir:verify-module module))))
  (let ((module (v05-loop-module)))
    (setf (mognitio.ir:ir-function-blocks (first (mognitio.ir:module-functions module)))
      (list (mognitio.ir:make-basic-block :id 0 :terminator '(:jump 1 ()))
            (mognitio.ir:make-basic-block :id 1 :terminator '(:jump 1 ()))))
    (is (mognitio.ir:verify-module module))))

(defun v05-run-module (module)
  (let* ((image (mognitio.elf:make-image (mognitio.amd64:encode (mognitio.machine:lower-module module))))
         (path (put-bytes (fresh-path ".elf") image)))
    (sb-posix:chmod (namestring path) #o700)
    (multiple-value-bind (out err code) (process-result (list (namestring path)))
      (same 0 code) (same "" err) (same (format nil "true~%") out))))

(deftest v05-cyclic-allocation
  (v05-run-module (v05-loop-module))
  (let* ((module (v05-loop-module)) (bs (entry-blocks module))
         (callee (mognitio.ir:make-ir-function :id 1 :result-type :int :entry 0
                   :blocks (list (mognitio.ir:make-basic-block :id 0
                     :instructions (list (mognitio.ir:make-instruction :result 0 :type :int :op :constant :value 99))
                     :terminator '(:return 0))))))
    (push (mognitio.ir:make-instruction :result 7 :type :int :op :call :value 1)
          (mognitio.ir:basic-block-instructions (third bs)))
    (setf (mognitio.ir:module-functions module) (append (mognitio.ir:module-functions module) (list callee)))
    (v05-run-module module)
    ;; The invariant limit is used only in the header; its value must survive
    ;; the call and the backedge even after its last textual use.
    (setf (mognitio.ir:basic-block-instructions (fourth bs))
          (list (mognitio.ir:make-instruction :result 6 :type :bool :op :constant :value 1)))
    (let* ((allocation (mognitio.regalloc:allocate-function (first (mognitio.ir:module-functions module))))
           (interval (find 1 (mognitio.regalloc:allocation-intervals allocation) :key #'mognitio.regalloc:interval-id)))
      (is (integerp (gethash 1 (mognitio.regalloc:allocation-locations allocation))))
      (is (> (mognitio.regalloc:interval-end interval) 12))
      (setf (mognitio.regalloc:interval-end interval) 12)
      (signals internal-failure (mognitio.regalloc:verify-allocation allocation)))
    (setf (mognitio.ir:ir-function-blocks (first (mognitio.ir:module-functions module))) (reverse bs))
    (v05-run-module module)))

(deftest v05-alternative-rpo
  (let* ((module (v05-loop-module)) (function (first (mognitio.ir:module-functions module)))
         (header (second (entry-blocks module)))
         (before (mapcar #'mognitio.ir:basic-block-id (mognitio.regalloc::block-order function))))
    (setf (mognitio.ir:instruction-op (first (mognitio.ir:basic-block-instructions header))) :ge
          (mognitio.ir:basic-block-terminator header) '(:branch 4 3 2))
    (is (not (equal before (mapcar #'mognitio.ir:basic-block-id (mognitio.regalloc::block-order function)))))
    (is (mognitio.ir:verify-module module))
    (v05-run-module module)))
