(in-package #:mognitio.tests)

(defun v06-i (id type op &rest args)
  (apply #'mognitio.ir:make-instruction :result id :type type :op op args))
(defun v06-test-pool ()
  (vector (make-text-payload :octets (hex-bytes "") :scalar-count 0)
          (make-text-payload :octets (hex-bytes "61") :scalar-count 1)))
(defun v06-root-fixture (&optional direct)
  (mognitio.ir:make-module :literal-pool (v06-test-pool) :functions
    (list
     (mognitio.ir:make-ir-function :id 0 :result-type :bool :entry 0 :blocks
       (list (mognitio.ir:make-basic-block :id 0 :instructions
         (list (v06-i 0 :string :const.text :value 1) ; dead, deliberately retained in Core
               (v06-i 1 :string :const.text :value 1) ; lives through both safepoints
               (v06-i 2 :int :constant :value 0)
               (v06-i 3 '(:function (:string) :string) :function :value 1)
               (v06-i 4 :string :const.text :value 1) ; last use is the call
               (if direct (v06-i 5 :string :call :value 1 :operands '(4))
                   (v06-i 5 :string :call.value :value '((:function (:string) :string) (1)) :operands '(3 4)))
               (v06-i 6 :int :text.length :operands '(5))
               (v06-i 7 :string :text.slice :operands '(5 2 6))
               (v06-i 8 :bool :text.equal :operands '(7 1))) :terminator '(:return 8))))
     (mognitio.ir:make-ir-function :id 1 :parameter-types '(:string) :result-type :string :entry 0 :blocks
       (list (mognitio.ir:make-basic-block :id 0 :parameters '((0 . :string)) :instructions
         (list (v06-i 1 :string :const.text :value 1)
               (v06-i 2 :string :text.concat :operands '(0 1))) :terminator '(:return 2)))))))
(defun v06-root-snapshot (plans)
  (loop for plan in plans collect
    (list (mognitio.roots:root-plan-function-id plan) (mognitio.roots:root-plan-capacity plan)
          (loop for s in (mognitio.roots:root-plan-sites plan) collect
            (list (mognitio.roots:root-site-block-id s) (mognitio.roots:root-site-instruction-index s)
                  (mognitio.roots:root-site-values s))))))

(deftest v06-root-call-and-last-use
  (dolist (direct '(nil t))
    (let* ((module (v06-root-fixture direct)) (plans (mognitio.roots:analyze-roots module)))
      ;; Function IDs, integers, dead values, and not-yet-created results are absent.
      (same '((0 2 ((0 5 (1 4)) (0 7 (1 5)))) (1 2 ((0 1 (0 1))))) (v06-root-snapshot plans))
      (is (mognitio.roots:verify-roots module plans))
      (same 0 (v06-evaluate-core module))))
  (let ((module (v06-native-ir "let f=function():int{1}; f()==1")))
    ;; Even a no-string call is a safepoint; its frame has zero slots.
    (same '((0 0 ((0 1 nil))) (1 0 nil)) (v06-root-snapshot (mognitio.roots:analyze-roots module)))))

(defun v06-root-loop-fixture (&optional endless)
  (let* ((entry (mognitio.ir:make-basic-block :id 0 :instructions
                  (list (v06-i 0 :string :const.text :value 1)
                        (v06-i 1 :string :const.text :value 1)
                        (v06-i 2 :string :const.text :value 1)
                        (v06-i 3 :int :constant :value 0)
                        (v06-i 4 :bool :constant :value 1)
                        (v06-i 11 :string :text.concat :operands '(1 1)))
                  :terminator '(:jump 1 (0 2))))
         (header (mognitio.ir:make-basic-block :id 1 :parameters '((5 . :string) (6 . :string))
                   :instructions (list (v06-i 7 :string :text.concat :operands '(5 1))) :terminator '(:jump 2 (7))))
         (join (mognitio.ir:make-basic-block :id 2 :parameters '((8 . :string))
                 :instructions (list (v06-i 9 :string :text.slice :operands '(8 3 3))
                                     (v06-i 10 :bool :text.equal :operands '(8 1)))
                 :terminator (if endless '(:jump 3 ()) '(:branch 4 3 4))))
         (back (mognitio.ir:make-basic-block :id 3 :terminator '(:jump 1 (8 6))))
         (exit (mognitio.ir:make-basic-block :id 4 :terminator '(:return 10))))
    (mognitio.ir:make-module :literal-pool (v06-test-pool) :functions
      (list (mognitio.ir:make-ir-function :id 0 :entry 0 :result-type :bool
              :blocks (append (list entry header join back) (unless endless (list exit))))))))

(deftest v06-root-edge-substitution-and-scc
  (dolist (endless '(nil t))
    (let* ((module (v06-root-loop-fixture endless)) (f (first (mognitio.ir:module-functions module)))
           (expected '((0 2 ((0 5 (0 1)) (1 0 (1 5)) (2 0 (1 8)))))))
      (same expected (v06-root-snapshot (mognitio.roots:analyze-roots module)))
      ;; Physical layout and DFS order are not semantic root evidence.
      (setf (mognitio.ir:ir-function-blocks f) (reverse (mognitio.ir:ir-function-blocks f)))
      (same expected (v06-root-snapshot (mognitio.roots:analyze-roots module)))
      (is (mognitio.regalloc:allocate-function f)))))

(deftest v06-root-corruption
  (dolist (mutate
           (list
            (lambda (p) (setf (mognitio.roots:root-plan-sites p) (rest (mognitio.roots:root-plan-sites p))))
            (lambda (p) (push (first (mognitio.roots:root-plan-sites p)) (mognitio.roots:root-plan-sites p)))
            (lambda (p) (incf (mognitio.roots:root-plan-capacity p)))
            (lambda (p) (decf (mognitio.roots:root-plan-capacity p)))
            (lambda (p) (setf (mognitio.roots:root-plan-function-id p) 99))
            (lambda (p) (setf (mognitio.roots:root-site-instruction-index (first (mognitio.roots:root-plan-sites p))) 6))
            (lambda (p) (setf (mognitio.roots:root-site-block-id (first (mognitio.roots:root-plan-sites p))) 99))
            (lambda (p) (setf (mognitio.roots:root-plan-sites p) (reverse (mognitio.roots:root-plan-sites p))))))
    (let* ((module (v06-root-fixture)) (plans (mognitio.roots:analyze-roots module)))
      (funcall mutate (first plans))
      (signals internal-failure (mognitio.roots:verify-roots module plans))))
  (dolist (wrong '((1) (1 4 5) (0 1 4) (1 2 4) (1 3 4) (1 4 4) (4 1) (1 999)))
    (let* ((module (v06-root-fixture)) (plans (mognitio.roots:analyze-roots module)))
      (setf (mognitio.roots:root-site-values (first (mognitio.roots:root-plan-sites (first plans)))) wrong)
      (signals internal-failure (mognitio.roots:verify-roots module plans))))
  (let* ((module (v06-root-loop-fixture)) (plans (mognitio.roots:analyze-roots module)))
    ;; A successor parameter is not yet defined at the predecessor safepoint.
    (setf (mognitio.roots:root-site-values (first (mognitio.roots:root-plan-sites (first plans)))) '(1 5))
    (signals internal-failure (mognitio.roots:verify-roots module plans)))
  (let* ((module (v06-root-fixture)) (plans (mognitio.roots:analyze-roots module)))
    ;; Prove the verifier does not call back into the producer.
    (replacing (mognitio.roots::analyze-function-roots (lambda (&rest args) (declare (ignore args)) (error "Producer used")))
      (is (mognitio.roots:verify-roots module plans)))
    (signals internal-failure (mognitio.roots:verify-roots module (rest plans)))
    (signals internal-failure (mognitio.roots:verify-roots module (reverse plans)))))

(deftest v06-text-helper-call-barriers
  (dolist (op '(:text.length :text.equal :text.not-equal :text.concat :text.slice))
    (let* ((module (v06-root-fixture t)) (function (first (mognitio.ir:module-functions module)))
           (block (first (mognitio.ir:ir-function-blocks function)))
           (type (case op (:text.length :int) ((:text.equal :text.not-equal) :bool) (otherwise :string)))
           (operands (case op (:text.length '(0)) (:text.slice '(0 2 2)) (otherwise '(0 0)))))
      (setf (mognitio.ir:basic-block-instructions block)
            (list (v06-i 0 :string :const.text :value 1)
                  (v06-i 1 :string :const.text :value 1)
                  (v06-i 2 :int :constant :value 0)
                  (v06-i 3 type op :operands operands)
                  (v06-i 4 :bool :text.equal :operands '(1 1)))
            (mognitio.ir:basic-block-terminator block) '(:return 4))
      (is (mognitio.ir:verify-module module))
      (let ((allocation (mognitio.regalloc:allocate-function function))
            (plan (first (mognitio.roots:analyze-roots module))))
        (same 2 (length (mognitio.regalloc:allocation-barriers allocation)))
        (is (integerp (gethash 1 (mognitio.regalloc:allocation-locations allocation))))
        (if (member op '(:text.concat :text.slice))
            (same '(0 1) (mognitio.roots:root-site-values (first (mognitio.roots:root-plan-sites plan))))
            (same nil (mognitio.roots:root-plan-sites plan)))
        (setf (gethash 1 (mognitio.regalloc:allocation-locations allocation)) :r8)
        (signals internal-failure (mognitio.regalloc:verify-allocation allocation))))))

(deftest v06-root-earlier-operands-and-receiver
  (let ((module (v06-native-ir "let f=function(a:string,b:string):string{a+b}; f(\"a\"+\"b\",\"c\"+\"d\")==\"abcd\"")))
    (same '((0 3 ((0 3 (1 2)) (0 6 (3 4 5)) (0 7 (3 6)))) (1 2 ((0 0 (0 1)))))
          (v06-root-snapshot (mognitio.roots:analyze-roots module))))
  (let ((module (v06-native-ir "let s=\"abc\"; s->slice(0,{let unused=\"x\"+\"y\";1})==\"a\"")))
    (same '((0 3 ((0 4 (0 2 3)) (0 6 (0)))))
          (v06-root-snapshot (mognitio.roots:analyze-roots module))))
  (let ((module (v06-native-ir "let s=\"a\"; (if(true){s+\"b\"}else{s+\"c\"})==\"ab\"")))
    (same '((0 2 ((1 1 (0 2)) (2 1 (0 4)))))
          (v06-root-snapshot (mognitio.roots:analyze-roots module)))))
