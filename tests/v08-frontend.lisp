(in-package #:mognitio.tests)

(deftest v08-type-syntax-and-binding-ast
  (let* ((program (parse-text "type Box<T> = struct { value: T; }; let value: Box<Box<int>> = Box<Box<int>> { value: Box<int> { value: 42 } }; true"))
         (decl (aref (program-statements program) 0))
         (binding (aref (program-statements program) 1))
         (type (local-binding-annotation binding)))
    (same "T" (token-text (aref (data-declaration-type-parameters decl) 0)))
    (same "Box" (token-text type))
    (same "Box<Box<int>>" (let ((span (token-span type)))
                            (subseq (source-text (span-source span)) (span-start span) (span-end span))))
    (same :int (token-kind (aref (type-syntax-arguments (aref (type-syntax-arguments type) 0)) 0))))
  (let* ((p (parse-text "let id :function<T,>(T):T= function<T,>(x: T): T { x }; true"))
         (fn (local-binding-initializer (aref (program-statements p) 0))))
    (same 1 (length (function-expression-type-parameters fn))))
  (let* ((p (parse-text "branch on (Result<int, string>::Ok(42)) { Result<int, string>::Ok(value) => true, else => false, }"))
         (pattern (branch-arm-selector (aref (branch-expression-arms (program-root p)) 0))))
    (same 2 (length (type-syntax-arguments (variant-pattern-name pattern))))))

(deftest v08-generic-call-syntactic-commitment
  (dolist (text '("f<T>(x)" "f < T > (x)" "f<Box<Box<int>>>(x)" "f<Unknown,>(x)"))
    (let ((call (program-root (parse-text text))))
      (is (typep call 'call-expression))
      (is (typep (call-expression-callee call) 'variable-reference))
      (same 1 (length (call-expression-type-arguments call)))))
  (dolist (text '("f < T" "f > (x)" "(f < T) > x"))
    (is (typep (program-root (parse-text text)) 'binary-expression)))
  (dolist (text '("f<>(x)" "f<int,,>(x)" "function<>(x: int): int { x }"
                  "type Box<> = struct { value: int; }; true"
                  "interface I<T> {} true"
                  "interface I { let f = function<T>(x: T): T; } true"
                  "implement Box<int> {} true"
                  "implement Box { let f = function<T>(x: T): T { x }; } true"
                  "f::<int>(42)"))
    (same :parse (diagnostic-phase (diagnostic-of (lambda () (parse-text text)))))))

(deftest v08-error-expression-ast
  (let* ((node (program-root (parse-text "try panic { \"stop\" }")))
         (panic (try-expression-operand node)))
    (is (typep node 'try-expression))
    (is (typep panic 'panic-expression))
    (is (typep (panic-expression-block panic) 'sequence-node)))
  (dolist (text '("panic {}" "panic { 42 }" "panic { let x: string = \"stop\"; x }"))
    (is (typep (program-root (parse-text text)) 'panic-expression)))
  (let ((node (program-root (parse-text "try parse(text) + 1"))))
    (is (typep node 'binary-expression))
    (is (typep (binary-expression-left node) 'try-expression)))
  (dolist (text '("panic \"stop\"" "panic(\"stop\")" "let try = 1; true" "let panic = 1; true"))
    (same :parse (diagnostic-phase (diagnostic-of (lambda () (parse-text text))))))
)

(deftest v081-function-type-syntax
  (let* ((binding (aref (program-statements (parse-text "let f:function(int):int=function(value:int):int{value}; true")) 0))
         (annotation (local-binding-annotation binding)))
    (is (typep annotation 'function-type-syntax))
    (same 1 (length (function-type-syntax-parameters annotation)))
    (same :int (token-kind (function-type-syntax-result annotation))))
  (let ((annotation (local-binding-annotation (aref (program-statements (parse-text "let id:function<A>(A):A=function<T>(value:T):T{value}; true")) 0))))
    (is (typep annotation 'generic-signature-syntax))
    (same "A" (token-text (aref (generic-signature-syntax-type-parameters annotation) 0))))
  (same :parse (diagnostic-phase (diagnostic-of (lambda () (parse-text "function consume(f:function<T>(T):T):int{1}")))))
  (is (typep (local-binding-annotation (aref (program-statements (parse-text "let x:function<T>(T):T=42; true")) 0))
             'generic-signature-syntax))
)
