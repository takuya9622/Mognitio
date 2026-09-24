(in-package #:mognitio.tests)

(deftest v04-typed-functions-and-order
  (dolist (source
            '("let subtotal = function(price: int, count: int): int { price * count }; let discounted = function(amount: int): int { amount - 20 }; discounted(subtotal(120, 3)) == 340"
              "let yes = function(): bool { true }; let value = function(): int { 42 }; branch when{(yes())=>{value() == 42},else=>{false}}"
              "let later = function(n: int): int { n * 2 }; let first = function(n: int): int { later(n) + later(2) }; first(3) == 10"
              "let add = function(a: int, b: int): int { a + b }; add(add(1, 2), add(3, 4)) == 10"
              "let pair = function(a: int, b: int): int { a * 10 + b }; var n: int = 1; pair(n, branch when{(true)=>{n = 2; n},else=>{0}}) == 12"
              "let twice = function(n: int): int { n * 2 }; let left: int = 7; left + twice(twice(3)) + left == 26"
              "let update = function(n: int): int { var copy: int = n; copy = copy + 1; copy }; var n: int = 5; let a: int = update(n); let b: int = update(n); a + b + n == 17"
              "let a = function(n: int): int { let local: int = n; local }; let b = function(n: int): int { let local: int = n + 1; local }; let n: int = 8; let local: int = 2; a(local) + b(local) + n == 13"
              "let unused = function(): int { 1 / 0 }; true"
              "let main = function(): int { 7 }; false == false"
              "let Void = function(never: int): int { let string = never; string }; Void(3) == 3"
              "let Int = function(Bool: bool): bool { Bool }; let Function: bool = true; let return1: bool = false; let bool1: bool = true; Int(Function) == bool1"))
    (v03-positive source :true))
  (v03-positive "let no = function(): bool { false }; no()" :false t)
  (v03-positive "let mixed = function(a: bool, b: int, c: bool, d: int, e: int, f: bool, g: int, h: bool): bool { branch when{(a)=>{branch when{(c)=>{false},else=>{branch when{(f)=>{false},else=>{branch when{(h)=>{(b == -9223372036854775808) == (d == 9223372036854775807)},else=>{false}}}}}}},else=>{false}} }; mixed(true, -9223372036854775808, false, 9223372036854775807, 8, false, 9, true)" :true)
  (v03-positive
   (with-output-to-string (out)
     (loop for i from 23 downto 0 do (format out "let f~D = function(x: int): int { ~A }; " i
                            (if (= i 23) "x" (format nil "f~D(x) + 1" (1+ i)))))
     (write-string "f0(5) == 28" out)) :true))

(deftest v04-return-paths
  (dolist (source
            '("let f = function(): int { return 7; }; f() == 7"
              "let f = function(b: bool): int { branch when{(b)=>{return 2;},else=>{3}} }; f(true) + f(false) == 5"
              "let f = function(b: bool): bool { branch when{(b)=>{return true;},else=>{return false;}} }; f(true) != f(false)"
              "let f = function(stop: bool, n: int): int { let x: int = branch when{(stop)=>{return n;},else=>{n + 1}}; x * 2 }; f(true, 3) + f(false, 3) == 11"
              "let f = function(): int { return 2; }; let g = function(): int { f() + 3 }; g() == 5"
              "let pair = function(a: int, b: int): int { a + b }; let f = function(): int { pair(branch when{(true)=>{return 7;},else=>{return 8;}}, 1 / 0) }; f() == 7"
              "let f = function(): int { branch when{(branch when{(false)=>{return 7;},else=>{return 8;}})=>{1 / 0},else=>{2 / 0}} }; f() == 8"
              "let f = function(): int { (branch when{(true)=>{return 7;},else=>{return 8;}}) + 1 / 0 }; f() == 7"
              "let f = function(): int { 3 + branch when{(true)=>{return 7;},else=>{return 8;}} }; f() == 7"
              "let f = function(): int { -(branch when{(true)=>{return 7;},else=>{return 8;}}) }; f() == 7"
              "let f = function(): int { return branch when{(true)=>{return 7;},else=>{return 8;}}; }; f() == 7"
              "let f = function(b: bool): int { var n: int = 1; let x: int = branch when{(b)=>{n = 2; return n;},else=>{n = 3; n}}; n + x }; f(false) == 6"
              "let f = function(b: bool): int { var n: int = 1; let x: int = branch when{(b)=>{n = 2; n},else=>{return 3;}}; n + x }; f(true) == 4"
              "let bad = function(n: int): int { 1 / n }; let f = function(): int { bad(branch when{(true)=>{return 8;},else=>{return 9;}}) }; f() == 8"))
    (v03-positive source :true))
  ;; All source functions remain present, but no call is emitted after a return.
  (let* ((module (native-ir "let bad = function(n: int): int { n / 0 }; let f = function(): int { bad(branch when{(true)=>{return 8;},else=>{return 9;}}) }; f() == 8"))
         (functions (mognitio.ir:module-functions module))
         (f (third functions)))
    (same 3 (length functions))
    (same 0 (loop for b in (mognitio.ir:ir-function-blocks f) sum
              (count :call.value (mognitio.ir:basic-block-instructions b) :key #'mognitio.ir:instruction-op)))
    (same 0 (count-if #'mognitio.ir:basic-block-parameters (mognitio.ir:ir-function-blocks f)))))

(deftest v04-reserved-words-and-grammar
  (let* ((source (text-source "function return int bool Function Int Bool return1 intValue bool1 void never string"))
         (tokens (lex-source source)))
    (same '(:function :return :int :bool :identifier :identifier :identifier :identifier
            :identifier :identifier :void :identifier :identifier :eof)
          (map 'list #'token-kind tokens)))
  (dolist (word '("function" "return" "int" "bool"))
    (dolist (template '("let ~A = function(): int { 1 }; true" "let f = function(~A: int): int { 1 }; true"
                        "let ~A = 1; true" "var ~A = 1; true"))
      (v03-reject (format nil template word) "parse")))
  (dolist (source '( "let f = function(n: never): int { 1 }; true"
                    "let f = function(n: Int): int { n }; true" "let f = function(): Unknown { 1 }; true"
                    "let f = function(n): int { n }; true" "let f = function(): int; true"
                    "let f = function(): int { 1 };; true" "let f = function(): int { 1 };"
                    "let f = function(n: int,): int { n }; true" "let f = function(): int { 1 }; f(1,) == 1"





                    "let f = function(): int { branch when{(true)=>{return 1;}} 2 }; true"
                    "let f = function(): int { 1 + return 2 }; true" "return true;" "int(1) == 1"))
    (v03-reject source "parse")))

(deftest v04-static-errors-and-cycles
  (dolist (source
            '("let f = function(): int { 1 }; let f = function(x: int): int { x }; true"
              "let g = function(): int { 1 }; let f = function(g: int): int { g }; true"
              "let f = function(): int { 1 }; let f = 2; true"
              "let f = function(): int { let f = 2; f }; true"
              "let f = function(): int { 1 }; branch when{(false)=>{var f = 1; true},else=>{true}}"
              "let f = function(x: int, x: int): int { x }; true"
              "let f = function(x: int): int { x = 1; x }; true"
              "let f = function(x: int): int { let x = 1; x }; true"
              "let f = function(x: int): int { branch when{(false)=>{let x = 2; x},else=>{x}} }; true"
              "let f = function(): int { x }; let x = 1; true"
              "let f = function(): int { let x: int = 1; x }; let g = function(): int { x }; true"
              "let f = function(x: int): int { x }; x == 1"
              "let f = function(): int { 1 }; f = 2; true"
              "let f: int = 1; f() == 1" "missing()" "let f = function(): int { 1 }; var saved = f; true"
              "let f = function(x: int): int { x }; f() == 1" "let f = function(x: int): int { x }; f(true) == 1"
              "let f = function(): int { true }; true" "let f = function(): int { return true; }; true"
              "let f = function(): int { branch when{(true)=>{return true;},else=>{1}} }; true"
              "let f = function(): int { branch when{(1)=>{return 1;},else=>{2}} }; true"
              "branch when{(true)=>{return true;},else=>{false}}"
              "let f = function(): int { let x = branch when{(true)=>{return 1;},else=>{return 2;}}; x }; true"
              "let f = function(): int { (branch when{(true)=>{return 1;},else=>{return 2;}}) + true }; true"
              "let f = function(): int { branch when{(branch when{(true)=>{return 1;},else=>{return 2;}})=>{1},else=>{true}} }; true"
              "let f = function(): int { var n: int = 0; n = branch when{(true)=>{return 1;},else=>{return 2;}}; true }; true"
              "let f = function(): int { var n: int = 0; n = branch when{(true)=>{return 1;},else=>{return 2;}}; missing }; true"
              "let f = function(): int { f() }; true"
              "let f = function(): int { g() }; let g = function(): int { f() }; true"
              "let f = function(): int { branch when{(false)=>{f()},else=>{1}} }; true"
              "let f = function(): int { var n: int = 1; n = branch when{(true)=>{return 1;},else=>{return 2;}}; f() }; true"
              "let f = function(): int { let x = x; x }; true"
              "let unused = function(): int { 9223372036854775808 }; true"))
    (v03-reject source "semantic")))

(deftest v04-call-runtime-order
  (dolist (pair '(("let f = function(a: int, b: int): int { 9223372036854775807 + 1 }; f(1 / 0, 1 % 0) == 0" "division by zero")
                  ("let f = function(a: int): int { 1 % 0 }; f(1) == 0" "remainder by zero")
                  ("let f = function(): int { return 9223372036854775807 + 1; }; f() == 0" "integer overflow")
                  ("let f = function(): int { 1 / 0 }; let unused: int = f(); true" "division by zero")
                  ("let f = function(): int { 1 % 0 }; let g = function(): int { f() + branch when{(true)=>{return 1;},else=>{return 2;}} }; g() == 0" "remainder by zero")))
    (v03-runtime (first pair) (second pair) t)))

(deftest v04-name-type-and-flow-boundaries
  (dolist (name '("Function" "Int" "Bool" "return1" "intValue" "bool1" "Void" "never" "string"))
    (v03-positive (format nil "let ~A = function(): bool { true }; ~A()" name name) :true)
    (v03-positive (format nil "let f = function(~A: bool): bool { ~A }; f(true)" name name) :true)
    (v03-positive (format nil "let ~A = true; ~A" name name) :true))
  (dolist (name '("Int" "Void" "never" "Unknown"))
    (v03-reject (format nil "let f = function(n: ~A): int { 1 }; true" name) "parse")
    (v03-reject (format nil "let f = function(): ~A { 1 }; true" name) "parse"))
  (dolist (text '("let int = 1; int == 1" "let bool = true; bool"
                  "let f = function(x: int = 1): int { x }; true" "let f = function(x: int): int { x }; f(x: 1) == 1"
                  "let f = function(): int { return 1 }; true" ))
    (v03-reject text "parse"))
  (dolist (text '("let f = function(x: int): int { branch when{(true)=>{branch when{(false)=>{let x = 2; x},else=>{1}}},else=>{1}} }; true"
                  "let f = function(x: int): int { let y = branch when{(true)=>{let x = 2; x},else=>{1}}; y }; true"
                  "let a = function(): int { b() }; let b = function(): int { c() }; let c = function(): int { a() }; true"
                  "let f = function(): int { 1 }; f(1) == 1"
                  "let f = function(): int { var x = branch when{(true)=>{return 1;},else=>{return 2;}}; x }; true"
                  "let g = function(a: int, b: int): int { a + b }; let f = function(): int { g(branch when{(true)=>{return 1;},else=>{return 2;}}, true) }; true"
                  "let f = function(): int { branch when{(false)=>{return false;},else=>{1}} }; true"))
    (v03-reject text "semantic"))
  (v03-positive "let f = function(stop: bool): int { branch when{(stop)=>{return 3;},else=>{4}} }; f(true) + f(false) == 7" :true)
  (v03-positive "let f = function(a: int, b: bool, c: int, d: bool, e: int, z: bool, g: int, h: bool): bool { branch when{(a == -9223372036854775808)=>{branch when{(b)=>{branch when{(c == 9223372036854775807)=>{branch when{(d)=>{false},else=>{branch when{(e == 3)=>{branch when{(z)=>{branch when{(g == -7)=>{h == false},else=>{false}}},else=>{false}}},else=>{false}}}}},else=>{false}}},else=>{false}}},else=>{false}} }; f(-9223372036854775808, true, 9223372036854775807, false, 3, true, -7, false)" :true)
  (v03-runtime "let f = function(a: int, b: int): int { 1 / 0 }; f(1, 1 % 0) == 0" "remainder by zero")
  (v03-runtime "let g = function(): int { 1 / 0 }; let f = function(): int { g() }; f() == 0" "division by zero")
  (v03-positive "let f = function(stop: bool): int { branch when{(stop)=>{return 3;},else=>{1 / 0}} }; f(true) == 3" :true)
  (v03-runtime "let f = function(stop: bool): int { branch when{(stop)=>{return 3;},else=>{1 / 0}} }; f(false) == 3" "division by zero"))

(deftest v04-parameter-annotations
  (dolist (space (list "" " " (string #\Tab) (string #\Newline)
                       (format nil "~C~C" #\Return #\Newline)))
    (v03-positive
     (format nil "let choose = function(n~A:~Aint, flag~A:~Abool): int { branch when{(flag)=>{n},else=>{0}} }; choose(7, true) == 7"
             space space space space)
     :true t))
  (v03-positive "let both = function(left:bool,right:bool):bool { branch when{(left)=>{right},else=>{false}} }; both(true,false)"
                :false t)
  (let* ((text (format nil "let f = function(~%  value : int,~%  flag: bool~%): int { branch when{(flag)=>{value},else=>{0}} }; f(7,true) == 7"))
         (program (parse-text text))
         (parameters (function-expression-parameters (local-binding-initializer (aref (program-statements program) 0)))))
    (same 2 (length parameters))
    (loop for parameter across parameters
          for name in '("value" "flag")
          for type in '("int" "bool")
          for whole in '("value : int" "flag: bool")
          do (same name (token-text (parameter-name parameter)))
             (same type (token-text (parameter-type parameter)))
             (let ((span (parameter-span parameter)))
               (same whole (subseq text (span-start span) (span-end span)))
               (same (program-source program) (span-source span)))))
  ;; Each invalid signature keeps its remaining program well formed.
  (dolist (text '("let f = function(int x): int { x }; true"
                  "let f = function(bool flag): bool { flag }; true"
                  "let f = function(x: int, bool flag): int { x }; true"
                  "let f = function(int x, flag: bool): int { x }; true"
                  "let f = function(x int): int { x }; true"
                  "let f = function(: int): int { 1 }; true"
                  "let f = function(x:): int { x }; true"
                  "let f = function(x:: int): int { x }; true"
                  "let f = function(x: int, flag bool): int { x }; true"
                  "let f = function(x: int): int { x }; f(x: 1) == 1"))
    (v03-reject text "parse"))
  (dolist (case (list
                 (list "let f = function(int x): int { x }; true" 1 18)
                 (list "let f = function(x int): int { x }; true" 1 20)
                 (list "let f = function(: int): int { 1 }; true" 1 18)
                 (list "let f = function(x:): int { x }; true" 1 20)
                 (list (format nil "let f = function(~%  x int~%): int { x }; true") 2 5)))
    (let ((diag (diagnostic-of (lambda () (parse-text (first case))))))
      (same :parse (diagnostic-phase diag))
      (same (second case) (diagnostic-line diag))
      (same (third case) (diagnostic-column diag))))
  (let ((diag (diagnostic-of (lambda () (check-program (parse-text "let f = function(x: Int): int { x }; true"))))))
    (same :semantic (diagnostic-phase diag)) (same 1 (diagnostic-line diag)) (same 21 (diagnostic-column diag)))
  (let* ((text "let f = function(x: int, x: bool): int { x }; true")
         (diag (diagnostic-of (lambda () (check-program (parse-text text))))))
    (same :semantic (diagnostic-phase diag))
    (same 1 (diagnostic-line diag))
    (same 26 (diagnostic-column diag))))
