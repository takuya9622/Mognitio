(in-package #:mognitio.tests)

(deftest v07-interface-requirement-syntax
  ;; Requirement signatures are declarations, not evaluated function values.
  (let* ((text "interface Named { let nameText = function(x: int,): string; } true")
         (program (parse-text text))
         (member (aref (contract-declaration-methods (aref (program-statements program) 0)) 0))
         (signature (named-member-value member))
         (checked (check-program program)))
    (same "nameText" (token-text (named-member-name member)))
    (same "nameText" (subseq text (span-start (token-span (named-member-name member)))
                                 (span-end (token-span (named-member-name member)))))
    (same "let nameText = function(x: int,): string;"
          (subseq text (span-start (node-span member)) (span-end (node-span member))))
    (same "function(x: int,): string;"
          (subseq text (span-start (node-span signature)) (span-end (node-span signature))))
    (same nil (function-expression-body signature))
    (same 1 (length (function-expression-parameters signature)))
    (same 1 (length (mognitio.semantic::checked-program-signatures checked)))
    (same 1 (length (mognitio.ir:module-functions (native-ir text)))))
  (v07-accept "interface Named{let nameText=function():string;let add=function(a:int,b:int,):int;}type U=struct{s:string;};implement U against Named{let nameText=function():string{this->s};let add=function(x:int,y:int):int{x+y};}let use=function(n:Named):bool{branch when{n->nameText()==\"ok\"=>n->add(2,3)==5,else=>false}};use(U{s:\"ok\"})")
  ;; Each rejection keeps valid surrounding declarations and a bool tail.
  (dolist (source
    '("interface I{function f():int;}true"
      "interface I{let f=function():int{1};}true"
      "interface I{var f=function():int;}true"
      "interface I{let f=function():int;let g=f;}true"
      "interface I{type Alias=int;}true"
      "interface I{let f=1+2;}true"
      "interface I{true;}true"
      "interface I{let f=function():int;f();}true"
      "let f=function():int;true"
      "let f=(function():int);true"
      "let f=function():int{1};let g=function():int{function():int;1};true"
      "type U=struct{};implement U{let f=function():int;}true"))
    (v03-reject source "parse")))

(deftest v07-reused-aggregate-padding
  ;; Dirty a block, keep its neighbor alive to prevent coalescing, collect,
  ;; then call the actual constructor helper. Inspect every unused word,
  ;; including a whole-block remainder too small to split.
  (dolist (pair '(("type Z=struct{};let z: Z=Z{};true" :struct.make 0)
                  ("type Z=enum{Empty;};let z: Z=Z::Empty;true" :enum.make 0)
                  ("type Z=struct{n:int;};let z: Z=Z{n:7};true" :struct.make 1)
                  ("type Z=enum{Item(int);};let z: Z=Z::Item(7);true" :enum.make 1)))
    (destructuring-bind (source op slots) pair
      (let ((helper (mognitio.native.runtime::value-helper-name (v07-operation (native-ir source) op))))
        (dolist (size '(40 48 56 80))
          (let* ((physical (if (>= (- size 40) 40) 40 size))
                 (caller
                   (append (v06-raw-frame) (v06-raw-allocate (- size 32))
                     '((:store-frame -8 :rax) (:mov-reg :rdx :rax) (:imm-rax 42))
                     (loop for offset from 32 below size by 8 collect `(:store-word :rdx ,offset :rax))
                     (v06-raw-allocate 8)
                     '((:store-frame -32 :rax) (:call (:runtime :collect)) (:imm-rax 7) (:store-out 0 :rax))
                     `((:call ,helper) (:load-frame :rdx -8) (:cmp-rax-rdx) (:jnz :bad)
                       (:load-word :rcx :rax 0) (:cmp-imm :rcx ,physical) (:jnz :bad))
                     (when (plusp slots) '((:load-word :rcx :rax 32) (:cmp-imm :rcx 7) (:jnz :bad)))
                     (loop for offset from (+ 32 (* 8 slots)) below physical by 8 append
                       `((:load-word :rcx :rax ,offset) (:test-rcx) (:jnz :bad)))
                     '((:imm-rax 1) (:jmp :done) (:label :bad) (:imm-rax 0)
                       (:label :done) (:imm-rdx 0) (:store-word :r15 0 :rdx)
                       (:mov-reg :rsp :rbp) (:pop-rbp) (:ret)))))
            (let ((mognitio.native.runtime::*test-options* '(:arena-unit 4096 :cap 4096 :validate t)))
              (multiple-value-bind (out err status) (v05-cross-abi source 0 caller)
                (same 0 status) (same "" err) (same (format nil "true~%") out)))))))))

(deftest v07-implementation-table-layout-order
  ;; Registry identity and visibility remain in source order. Only emitted
  ;; tables are sorted, first by concrete type, then by contract.
  (let* ((source "type A=struct{};type B=struct{};interface I{}interface J{}implement B against J{}implement A against J{}implement B against I{}implement A against I{}true")
         (module (native-ir source))
         (registry (mognitio.semantic:value-context-implementations (mognitio.ir:module-values module))))
    (flet ((identities ()
             (loop for impl across registry collect
               (list (implementation-info-id impl) (second (implementation-info-concrete impl))
                     (second (implementation-info-contract impl))))))
      (same '((0 1 3) (1 0 3) (2 1 2) (3 0 2)) (identities))
      (multiple-value-bind (bytes symbols) (mognitio.amd64:encode (mognitio.machine:lower-module module))
        (let ((previous -1))
          (dolist (row '((3 0 2) (1 0 3) (2 1 2) (0 1 3)))
            (let ((offset (mognitio.object:image-symbol-offset (gethash (list :method-table (first row)) symbols))))
              (is (> offset previous)) (setf previous offset)
              (same 0 (mod offset 8))
              (same (second row) (image-integer bytes offset 8))
              (same (third row) (image-integer bytes (+ offset 8) 8))
              (same 0 (image-integer bytes (+ offset 16) 8))))))
      (same '((0 1 3) (1 0 3) (2 1 2) (3 0 2)) (identities)))))
