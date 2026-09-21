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
