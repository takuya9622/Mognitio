(in-package #:mognitio.tests)

(deftest v05-checked-metadata-mutations
  (dolist (mutation
     (list
       (lambda (checked node) (setf (completion-normal-type (checked-completion checked node)) :void))
       (lambda (checked node) (setf (completion-exits (checked-completion checked node)) '((:return 99 nil nil))))
       (lambda (checked node) (setf (completion-may-return (checked-completion checked node)) t))
       (lambda (checked node) (setf (mognitio.semantic::loop-info-owner (checked-loop checked node)) 99))
       (lambda (checked node) (setf (mognitio.semantic::loop-info-plain (checked-loop checked node)) t))
       (lambda (checked node) (setf (mognitio.semantic::loop-info-types (checked-loop checked node)) '(:int)))
       (lambda (checked node) (declare (ignore node)) (clrhash (mognitio.semantic::checked-program-controls checked)))))
    (let* ((checked (check-program (parse-text "loop {break true;}")))
           (node (program-root (checked-program-program checked))))
      (funcall mutation checked node)
      (signals internal-failure (compile-program checked))
      (signals internal-failure (mognitio.ir:lower-program checked))))
  (dolist (text '("1 == 1" "-1 == -1" "-9223372036854775808 < 0"))
    (let* ((checked (check-program (parse-text text)))
           (node (binary-expression-left (program-root (checked-program-program checked)))))
      (setf (gethash node (mognitio.semantic::checked-program-literals checked)) 0)
      (signals internal-failure (compile-program checked))
      (signals internal-failure (mognitio.ir:lower-program checked))))
  (let* ((checked (check-program (parse-text "let f=function(): int {1}; let g=function(): int {2}; (branch when{(true)=>{f},else=>{g}})()==1")))
         (call (binary-expression-left (program-root (checked-program-program checked))))
         (callee (call-expression-callee call)))
    (setf (completion-targets (checked-completion checked callee)) '(1)
          (mognitio.semantic::call-info-targets (checked-call checked call)) '(1))
    (signals internal-failure (compile-program checked))
    (signals internal-failure (mognitio.ir:lower-program checked)))

  (let* ((checked (check-program (parse-text "let f=function(x: int): int {x}; f(1)==1")))
         (symbol (aref (checked-program-bindings checked) 1)))
    (setf (local-symbol-static-target symbol) 1)
    (signals internal-failure (compile-program checked)))
  (let* ((checked (check-program (parse-text "let f=function(): int {1}; let selected:int=1; true")))
         (symbol (aref (checked-program-bindings checked) 1)))
    (setf (local-symbol-static-target symbol) 1)
    (signals internal-failure (compile-program checked))))

(deftest v05-independent-dominance
  ;; Removing a proposed dominator must disconnect the use block from entry.
  ;; This reachability oracle does not use the verifier's dominator equations.
  (labels ((reachable-without (function target removed)
             (let ((pending (list (mognitio.ir:ir-function-entry function))) (seen nil))
               (loop while pending for id = (pop pending) do
                 (unless (or (= id removed) (member id seen))
                   (when (= id target) (return-from reachable-without t))
                   (push id seen)
                   (let* ((block (find id (mognitio.ir:ir-function-blocks function) :key #'mognitio.ir:basic-block-id))
                          (term (mognitio.ir:basic-block-terminator block)))
                     (case (first term)
                       (:jump (push (second term) pending))
                       (:branch (push (third term) pending) (push (fourth term) pending))))))
               nil)))
    (let* ((baseline (v05-loop-module)) (function (first (mognitio.ir:module-functions baseline))) (defs nil))
      (dolist (block (mognitio.ir:ir-function-blocks function))
        (dolist (p (mognitio.ir:basic-block-parameters block)) (push (cons (car p) (mognitio.ir:basic-block-id block)) defs))
        (dolist (i (mognitio.ir:basic-block-instructions block)) (push (cons (mognitio.ir:instruction-result i) (mognitio.ir:basic-block-id block)) defs)))
      (dolist (definition defs)
        (dolist (target (mognitio.ir:ir-function-blocks function))
          (let* ((id (mognitio.ir:basic-block-id target))
                 (dominates (not (reachable-without function id (cdr definition))))
                 (module (v05-loop-module))
                 (block (find id (entry-blocks module) :key #'mognitio.ir:basic-block-id)))
            (setf (mognitio.ir:basic-block-instructions block)
                  (append (mognitio.ir:basic-block-instructions block)
                          (list (mognitio.ir:make-instruction :result 100 :type :bool :op :eq :operands (list (car definition) (car definition))))))
            (if dominates (is (mognitio.ir:verify-module module))
                (signals internal-failure (mognitio.ir:verify-module module)))))))))

(defun v05-function-cycle-module ()
  (let* ((type '(:function nil :int))
         (module (native-ir "let f=function(): int {1}; let g=function(): int {2}; true"))
         (entry (first (mognitio.ir:module-functions module))))
    (setf (mognitio.ir:ir-function-blocks entry)
      (list
        (mognitio.ir:make-basic-block :id 0
          :instructions (list (mognitio.ir:make-instruction :result 0 :type type :op :function :value 1)
                              (mognitio.ir:make-instruction :result 1 :type type :op :function :value 2)
                              (mognitio.ir:make-instruction :result 2 :type :bool :op :constant :value 0))
          :terminator '(:jump 1 (0)))
        (mognitio.ir:make-basic-block :id 1 :parameters (list (cons 3 type))
          :instructions (list (mognitio.ir:make-instruction :result 4 :type :int :op :call.value :value (list type '(1 2)) :operands '(3)))
          :terminator '(:branch 2 2 3))
        (mognitio.ir:make-basic-block :id 2 :terminator '(:jump 1 (1)))
        (mognitio.ir:make-basic-block :id 3 :terminator '(:return 2))))
    module))

(deftest v05-cyclic-function-candidate-fixed-point
  (let* ((module (v05-function-cycle-module)) (entry (first (mognitio.ir:module-functions module))))
    (is (mognitio.ir:verify-module module))
    (setf (mognitio.ir:ir-function-blocks entry) (reverse (mognitio.ir:ir-function-blocks entry)))
    (is (mognitio.ir:verify-module module)))
  (let* ((module (v05-function-cycle-module)) (blocks (entry-blocks module)))
    ;; A call annotation must not seed an otherwise unsupported cyclic value.
    (setf (mognitio.ir:basic-block-terminator (first blocks)) '(:jump 1 (3))
          (mognitio.ir:basic-block-terminator (third blocks)) '(:jump 1 (3)))
    (let ((diag (diagnostic-of (lambda () (mognitio.ir:verify-module module)))))
      (same :internal (diagnostic-phase diag))
      (same "Empty function candidate set" (diagnostic-message diag))))
  (dolist (targets '((1) (2) (1 1 2) (0 1 2) (1 2 99) nil))
    (let* ((module (v05-function-cycle-module)) (call (first (mognitio.ir:basic-block-instructions (second (entry-blocks module))))))
      (setf (second (mognitio.ir:instruction-value call)) targets)
      (signals internal-failure (mognitio.ir:verify-module module))))
  (dolist (count '(1 2 1000))
    (let ((edges (make-hash-table)))
      (dotimes (id count) (setf (gethash id edges) (list (cons (mod (1+ id) count) nil))))
      (signals internal-failure
        (check-call-graph (loop for id below count collect id) edges
                          (lambda (span) (declare (ignore span)) (internal-error "Cycle")))))))

(deftest v05-handwritten-void-abi
  (let* ((forms
          '((:align-stack) (:clear-frame) (:call (:function 0)) (:mov-eax 60) (:syscall) (:ud2)
            (:label (:function 0)) (:push-rbp) (:mov-reg :rbp :rsp)
            (:push-zero) (:push-zero) (:push-zero) (:push-zero)
            (:push-zero) (:push-zero) (:push-zero) (:push-zero)
            (:store-frame -8 :rsp) (:store-frame -16 :rbp) (:imm-rax 2) (:store-frame -24 :rax)
            (:label :again)
            (:imm-rax 0) (:store-out 0 :rax) (:imm-rax 7) (:store-out 8 :rax)
            (:imm-rax 0) (:store-out 16 :rax) (:imm-rax 1) (:store-out 24 :rax)
            (:call (:function 1)) (:test) (:jnz :bad)
            (:mov-reg :rax :rsp) (:load-frame :rcx -8) (:cmp) (:jnz :bad)
            (:mov-reg :rax :rbp) (:load-frame :rcx -16) (:cmp) (:jnz :bad)
            (:load-frame :rax -24) (:imm-rcx 1) (:sub) (:store-frame -24 :rax) (:test) (:jnz :again)
            (:mov-edi 0) (:mov-reg :rsp :rbp) (:pop-rbp) (:ret)
            (:label (:function 1)) (:push-rbp) (:mov-reg :rbp :rsp)
            (:mov-reg :rax :rsp) (:imm-rcx 16) (:cqo) (:idiv) (:mov-rax-rdx) (:test) (:jnz :bad)
            (:load-frame :rax 16) (:test) (:jnz :bad)
            (:load-frame :rax 24) (:imm-rcx 7) (:cmp) (:jnz :bad)
            (:load-frame :rax 32) (:test) (:jnz :bad)
            (:load-frame :rax 40) (:imm-rcx 1) (:cmp) (:jnz :bad)
            (:imm-rax 99) (:mov-reg :r8 :rax) (:mov-reg :r9 :rax) (:mov-reg :r10 :rax) (:mov-reg :r11 :rax)
            (:imm-rax 0) (:mov-reg :rsp :rbp) (:pop-rbp) (:ret)
            (:label :bad) (:mov-edi 99) (:mov-eax 60) (:syscall) (:ud2)))
         (image (mognitio.elf:make-image (mognitio.amd64:encode (apply #'machine forms))))
         (path (put-bytes (fresh-path ".elf") image)))
    (sb-posix:chmod (namestring path) #o700)
    (multiple-value-bind (out err code) (process-result (list (namestring path)))
      (same 0 code) (same "" out) (same "" err))))

(deftest v05-host-void-and-dispatch-boundary
  (is (null (symbol-package mognitio.backend.cl::*void-value*)))
  (let* ((checked (check-program (parse-text "let f=function(): bool {true}; f()")))
         (form (mognitio.backend.cl::program-form checked)))
    (labels ((corrupt-dispatch (node)
               (cond ((atom node) node)
                     ((eq (first node) 'cl:case) (cons 'cl:case (cons 999 (cddr node))))
                     (t (mapcar #'corrupt-dispatch node)))))
      (let ((function (compile nil (list 'lambda nil (corrupt-dispatch form)))))
        (signals internal-failure (funcall function))))))

(defun v05-cross-abi (source owner handwritten &optional mutate)
  ;; Replace one unit only, after production lowering has generated both sides.
  ;; The opposite side retains production allocation, frame and call lowering.
  (let ((layout (fdefinition 'mognitio.object:layout-units)) (seen nil) code)
    (replacing (mognitio.object:layout-units
                 (lambda (units)
                   (dolist (unit units)
                     (let ((id (mognitio.object:code-unit-owner unit)))
                       (cond
                         ((eql id owner)
                          (is (not seen)) (setf seen t)
                          (setf (mognitio.object:code-unit-instructions unit)
                                (apply #'machine handwritten)))
                         ((and mutate (eql id (- 1 owner)))
                          (setf (mognitio.object:code-unit-instructions unit)
                                (apply #'machine
                                  (funcall mutate
                                    (mapcar (lambda (i)
                                              (cons (mognitio.machine:instruction-opcode i)
                                                    (copy-list (mognitio.machine:instruction-operands i))))
                                            (mognitio.object:code-unit-instructions unit)))))))))
                   (funcall layout units)))
      (setf code (mognitio.machine:lower-module (native-ir source))))
    (is seen)
    (let ((path (put-bytes (fresh-path ".elf")
                  (mognitio.elf:make-image (mognitio.amd64:encode code)))))
      (sb-posix:chmod (namestring path) #o700)
      (process-result (list (namestring path))))))

(defun v05-cross-abi-source (body tail)
  (format nil "let probe = function(v0: void, a: int, v1: void, b: bool,
                                   c: int, v2: void, d: bool, e: int): void { ~A };
               ~A" body tail))

(deftest v05-handwritten-caller-generated-callee
  (let ((source (v05-cross-abi-source
                 "branch when{(a != 7)=>{let bad:int=1/0;}}; branch when{(b)=>{},else=>{let bad:int=1/0;}};
                  branch when{(c != 11)=>{let bad:int=1/0;}}; branch when{(d)=>{let bad:int=1/0;}};
                  branch when{(e != 13)=>{let bad:int=1/0;}};" "true"))
        (caller
          (append
            '((:label (:function 0)) (:push-rbp) (:mov-reg :rbp :rsp))
            (loop repeat 12 collect '(:push-zero))
            '((:store-frame -8 :rsp) (:store-frame -16 :rbp)
              (:imm-rax 2) (:store-frame -24 :rax) (:label :again)
              (:imm-rax 0) (:store-out 0 :rax) (:imm-rax 7) (:store-out 8 :rax)
              (:imm-rax 0) (:store-out 16 :rax) (:imm-rax 1) (:store-out 24 :rax)
              (:imm-rax 11) (:store-out 32 :rax) (:imm-rax 0) (:store-out 40 :rax)
              (:store-out 48 :rax) (:imm-rax 13) (:store-out 56 :rax)
              (:call (:function 1)) (:test) (:jnz :bad)
              (:mov-reg :rax :rsp) (:load-frame :rcx -8) (:cmp) (:jnz :bad)
              (:mov-reg :rax :rbp) (:load-frame :rcx -16) (:cmp) (:jnz :bad)
              (:load-frame :rax -24) (:imm-rcx 1) (:sub)
              (:store-frame -24 :rax) (:test) (:jnz :again)
              (:imm-rax 1) (:mov-reg :rsp :rbp) (:pop-rbp) (:ret)
              (:label :bad) (:mov-edi 99) (:mov-eax 60) (:syscall) (:ud2)))))
    (multiple-value-bind (out err code) (v05-cross-abi source 0 caller)
      (same 0 code) (same (format nil "true~%") out) (same "" err))
    ;; Compacting the first int over its preceding void slot must be detected.
    (multiple-value-bind (out err code)
        (v05-cross-abi source 0 caller
          (lambda (forms)
            (let ((load (find '(:load-frame :rax 24) forms :test #'equal)))
              (is load) (setf (third load) 16))
            forms))
      (same 4 code) (same "" out) (is (search "division by zero" err)))
    ;; A nonzero void result must fail the independent caller's RAX check.
    (multiple-value-bind (out err code)
        (v05-cross-abi source 0 caller
          (lambda (forms)
            (is (member '(:ret) forms :test #'equal))
            (loop for form in forms
                  when (equal form '(:ret)) collect '(:imm-rax 9)
                  collect form)))
      (same 99 code) (same "" out) (same "" err))))

(deftest v05-generated-caller-handwritten-callee
  (let ((source (v05-cross-abi-source ""
                 "var i: int=0; var total: int=0;
                  loop while(i < 3){
                    let a: int=i+10; let b: int=i+20; let c: int=i+30;
                    let d: int=i+40; let e: int=i+50; let f: int=i+60;
                    probe(void, 7, void, true, 11, void, false, 13);
                    total=total+a+b+c+d+e+f;
                    i=i+1;
                  };
                  total == 648"))
        (callee
          (append
            '((:label (:function 1)) (:push-rbp) (:mov-reg :rbp :rsp)
              (:mov-reg :rax :rsp) (:imm-rcx 16) (:cqo) (:idiv)
              (:mov-rax-rdx) (:test) (:jnz :bad))
            ;; These offsets and values are ABI expectations, not lowerer output.
            (loop for offset in '(16 24 32 40 48 56 64 72)
                  for value in '(0 7 0 1 11 0 0 13)
                  append (list (list :load-frame :rax offset)
                               (list :imm-rcx value) '(:cmp) '(:jnz :bad)))
            '((:imm-rax 99) (:mov-reg :r8 :rax) (:mov-reg :r9 :rax)
              (:mov-reg :r10 :rax) (:mov-reg :r11 :rax)
              (:imm-rax 0) (:mov-reg :rsp :rbp) (:pop-rbp) (:ret)
              (:label :bad) (:mov-edi 99) (:mov-eax 60) (:syscall) (:ud2)))))
    (multiple-value-bind (out err code) (v05-cross-abi source 1 callee)
      (same 0 code) (same (format nil "true~%") out) (same "" err))
    ;; The same compacted-slot mistake on the generated caller is also rejected.
    (multiple-value-bind (out err code)
        (v05-cross-abi source 1 callee
          (lambda (forms)
            (let ((store (find '(:store-out 8 :rax) forms :test #'equal)))
              (is store) (setf (second store) 0))
            forms))
      (same 99 code) (same "" out) (same "" err))))
