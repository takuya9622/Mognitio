(in-package #:mognitio.tests)

(defun v06-gc-dump-forms ()
  ;; Test adapter writes a bounded context record and existing arenas. No heap
  ;; allocation or collector call is introduced by observation.
  '((:label :gc-dump) (:store-word :r15 24 :rax)
    (:mov-reg :rsi :r15) (:mov-edx 208) (:mov-edi 2) (:mov-eax 1) (:syscall)
    (:cmp-imm :rax 208) (:jnz :gc-dump-bad) (:load-word :r8 :r15 8)
    (:label :gc-dump-arena) (:cmp-imm :r8 0) (:jz :gc-dump-done)
    (:mov-reg :rsi :r8) (:load-word :rdx :r8 8)
    (:label :gc-dump-write) (:mov-edi 2) (:mov-eax 1) (:syscall)
    (:test) (:jle :gc-dump-bad) (:add-rsi) (:sub-rdx) (:jnz :gc-dump-write)
    (:load-word :r8 :r8 0) (:jmp :gc-dump-arena)
    (:label :gc-dump-done) (:load-word :rax :r15 24) (:jmp :print)
    (:label :gc-dump-bad) (:mov-edi 97) (:mov-eax 60) (:syscall) (:ud2)))

(defun v06-gc-artifact (source options &optional caller)
  (let ((original (fdefinition 'mognitio.object:layout-units)))
    (replacing (mognitio.object:layout-units
                 (lambda (units)
                   (let ((entry (first units)))
                     (setf (mognitio.object:code-unit-instructions entry)
                           (mapcar (lambda (inst)
                                     (if (and (eq (mognitio.machine:instruction-opcode inst) :jmp)
                                              (equal (mognitio.machine:instruction-operands inst) '(:print)))
                                         (first (machine '(:jmp :gc-dump))) inst))
                                   (mognitio.object:code-unit-instructions entry))))
                   (when caller
                     (setf (mognitio.object:code-unit-instructions
                            (find 0 units :key #'mognitio.object:code-unit-owner))
                           (apply #'machine caller)))
                   (funcall original
                     (append units (list (mognitio.object:make-code-unit :owner :gc-dump
                                          :instructions (apply #'machine (v06-gc-dump-forms))))))))
      (v06-runtime-artifact source options))))

(defvar *v06-gc-source*)

(defun v06-check-heap (artifact mode)
  (multiple-value-bind (out err status)
      (process-result (list "python3" (namestring (root-path "tests/v06-heap-check.py"))
                            (namestring artifact) mode
                            (namestring (put-text (fresh-path) *v06-gc-source*))) :timeout 60)
    (same 0 status) (same "" err) (is (search "NATIVE_GC_OK" out))
    (format t "~A" out)))

(defparameter *v06-gc-source*
  "let make=function(s:string):string{s+\"😀\\0\"}; let dead: string=\"discard\"+\"me\"; let hold: string=\"日\"+\"😀\\0\"; var carry: string=\"\"; var i: int=0; var good: bool=true; loop while(i<100000){let t: string=make(\"Aあ\"); let c: string=t->slice(1,4); branch when{(c!=\"あ😀\\0\")=>{good=false; break;}}; carry=c; i=i+1;}; branch when{(good)=>{branch when{(hold==\"日😀\\0\")=>{carry==\"あ😀\\0\"},else=>{false}}},else=>{false}}")

(deftest v06-native-gc-bounded-reclamation
  (dolist (stress '(nil t))
    (v06-check-heap
      (v06-gc-artifact *v06-gc-source*
                       (list :arena-unit 65536 :cap 65536 :trace t :validate t :stress stress))
      "reclamation"))
  (v06-expect-native *v06-gc-source* :true)
  (dolist (mutation '(:no-sweep :all-mark))
    (multiple-value-bind (out err status)
        (process-result (list (namestring
                               (v06-runtime-artifact *v06-gc-source*
                                 (list :arena-unit 65536 :cap 65536 :mutation mutation)))))
      (same 4 status) (same "" out) (same (format nil "runtime: allocation_failed~%") err))))

(defun v06-raw-allocate (bytes)
  `((:imm-rax ,bytes) (:store-out 0 :rax) (:imm-rax 0) (:store-out 8 :rax)
    (:call (:runtime :allocate))))
(defun v06-raw-frame ()
  (append '((:label (:function 0)) (:push-rbp) (:mov-reg :rbp :rsp))
          (loop repeat 12 collect '(:push-zero))
          '((:imm-rax 2) (:store-frame -40 :rax) (:lea-base :rax :rbp -48)
            (:store-word :r15 0 :rax))))
(defun v06-raw-finish ()
  '((:imm-rax 0) (:store-word :r15 0 :rax) (:imm-rax 1)
    (:mov-reg :rsp :rbp) (:pop-rbp) (:ret)))

(deftest v06-native-gc-split-coalesce-and-growth
  ;; Handwritten calls expose physical block geometry independently of text
  ;; lowering. Zero-filled mmap bytes form valid NUL scalars only when lengths
  ;; are zero; this fixture's checker inspects geometry, not artificial text.
  (dolist (pair '((3992 "split40") (4000 "whole32")))
    (v06-check-heap
      (v06-gc-artifact "let x: string=\"a\"+\"b\"; true" '(:arena-unit 4096 :cap 4096)
        (append (v06-raw-frame) (v06-raw-allocate (first pair)) (v06-raw-finish))) (second pair)))
  (v06-check-heap
    (v06-gc-artifact "let x: string=\"a\"+\"b\"; true" '(:arena-unit 4096 :cap 4096)
      (append (v06-raw-frame) (v06-raw-allocate 968) (v06-raw-allocate 968)
              (v06-raw-allocate 1968) '((:store-frame -32 :rax) (:call (:runtime :collect)))
              (v06-raw-allocate 1768) (v06-raw-finish))) "coalesce")
  (v06-check-heap
    (v06-gc-artifact "let x: string=\"a\"+\"b\"; true" '(:arena-unit 4096 :cap 32768 :validate t)
      (append (v06-raw-frame) (v06-raw-allocate 3000) '((:store-frame -32 :rax))
              (v06-raw-allocate 9000) '((:store-frame -24 :rax) (:call (:runtime :collect)))
              (v06-raw-finish))) "growth"))
