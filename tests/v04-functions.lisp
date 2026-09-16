(in-package #:mognitio.tests)

(deftest v04-typed-functions-and-order
  (dolist (source
            '("function subtotal(int price, int count): int { price * count } function discounted(int amount): int { amount - 20 } discounted(subtotal(120, 3)) == 340"
              "function yes(): bool { true } function value(): int { 42 } if(yes()){value() == 42}else{false}"
              "function first(int n): int { later(n) + later(2) } function later(int n): int { n * 2 } first(3) == 10"
              "function add(int a, int b): int { a + b } add(add(1, 2), add(3, 4)) == 10"
              "function pair(int a, int b): int { a * 10 + b } var n = 1; pair(n, if(true){n = 2; n}else{0}) == 12"
              "function twice(int n): int { n * 2 } let left = 7; left + twice(twice(3)) + left == 26"
              "function update(int n): int { var copy = n; copy = copy + 1; copy } var n = 5; let a = update(n); let b = update(n); a + b + n == 17"
              "function a(int n): int { let local = n; local } function b(int n): int { let local = n + 1; local } let n = 8; let local = 2; a(local) + b(local) + n == 13"
              "function unused(): int { 1 / 0 } true"
              "function main(): int { 7 } false == false"
              "function void(int never): int { let string = never; string } void(3) == 3"
              "function Int(bool Bool): bool { Bool } let Function = true; let return1 = false; let bool1 = true; Int(Function) == bool1"))
    (v03-positive source :true))
  (v03-positive "function no(): bool { false } no()" :false t)
  (v03-positive "function mixed(bool a, int b, bool c, int d, int e, bool f, int g, bool h): bool { if(a){if(c){false}else{if(f){false}else{if(h){(b == -9223372036854775808) == (d == 9223372036854775807)}else{false}}}}else{false} } mixed(true, -9223372036854775808, false, 9223372036854775807, 8, false, 9, true)" :true)
  (v03-positive
   (with-output-to-string (out)
     (dotimes (i 24) (format out "function f~D(int x): int { ~A } " i
                            (if (= i 23) "x" (format nil "f~D(x) + 1" (1+ i)))))
     (write-string "f0(5) == 28" out)) :true))

(deftest v04-return-paths
  (dolist (source
            '("function f(): int { return 7; } f() == 7"
              "function f(bool b): int { if(b){return 2;}else{3} } f(true) + f(false) == 5"
              "function f(bool b): bool { if(b){return true;}else{return false;} } f(true) != f(false)"
              "function f(bool stop, int n): int { let x = if(stop){return n;}else{n + 1}; x * 2 } f(true, 3) + f(false, 3) == 11"
              "function f(): int { return 2; } function g(): int { f() + 3 } g() == 5"
              "function pair(int a, int b): int { a + b } function f(): int { pair(if(true){return 7;}else{return 8;}, 1 / 0) } f() == 7"
              "function f(): int { if(if(false){return 7;}else{return 8;}){1 / 0}else{2 / 0} } f() == 8"
              "function f(): int { (if(true){return 7;}else{return 8;}) + 1 / 0 } f() == 7"
              "function f(): int { 3 + if(true){return 7;}else{return 8;} } f() == 7"
              "function f(): int { -(if(true){return 7;}else{return 8;}) } f() == 7"
              "function f(): int { var n = 1; n = if(true){return 7;}else{return 8;}; let unused = 1 / 0; n } f() == 7"
              "function f(): int { return if(true){return 7;}else{return 8;}; } f() == 7"
              "function f(bool b): int { var n = 1; let x = if(b){n = 2; return n;}else{n = 3; n}; n + x } f(false) == 6"
              "function f(bool b): int { var n = 1; let x = if(b){n = 2; n}else{return 3;}; n + x } f(true) == 4"
              "function bad(int n): int { 1 / n } function f(): int { bad(if(true){return 8;}else{return 9;}) } f() == 8"))
    (v03-positive source :true))
  ;; All source functions remain present, but no call is emitted after a return.
  (let* ((module (native-ir "function bad(int n): int { n / 0 } function f(): int { bad(if(true){return 8;}else{return 9;}) } f() == 8"))
         (functions (mognitio.ir:module-functions module))
         (f (third functions)))
    (same 3 (length functions))
    (same 0 (loop for b in (mognitio.ir:ir-function-blocks f) sum
              (count :call (mognitio.ir:basic-block-instructions b) :key #'mognitio.ir:instruction-op)))
    (same 0 (count-if #'mognitio.ir:basic-block-parameters (mognitio.ir:ir-function-blocks f)))))

(deftest v04-reserved-words-and-grammar
  (let* ((source (text-source "function return int bool Function Int Bool return1 intValue bool1 void never string"))
         (tokens (lex-source source)))
    (same '(:function :return :int :bool :identifier :identifier :identifier :identifier
            :identifier :identifier :identifier :identifier :identifier :eof)
          (map 'list #'token-kind tokens)))
  (dolist (word '("function" "return" "int" "bool"))
    (dolist (template '("function ~A(): int { 1 } true" "function f(int ~A): int { 1 } true"
                        "let ~A = 1; true" "var ~A = 1; true"))
      (v03-reject (format nil template word) "parse")))
  (dolist (source '("function f(): void { 1 } true" "function f(never n): int { 1 } true"
                    "function f(Int n): int { n } true" "function f(): Unknown { 1 } true"
                    "function f(n): int { n } true" "function f(): int; true"
                    "function f(): int { 1 }; true" "function f(): int { 1 }"
                    "function f(int n,): int { n } true" "function f(): int { 1 } f(1,) == 1"
                    "function f(): int { 1 } f(); true" "function f(): int { 1 } (f)() == 1"
                    "function f(): int { 1 } f()() == 1" "let a = 1; function f(): int { 1 } true"
                    "function f(): int { function g(): int { 1 } 1 } true"
                    "function f(): int { return; } true" "function f(): int { return 1; 2 } true"
                    "function f(): int { return 1; let x = 2; x } true"
                    "function f(): int { if(true){return 1;} 2 } true"
                    "function f(): int { 1 + return 2 } true" "return true;" "int(1) == 1"))
    (v03-reject source "parse")))

(deftest v04-static-errors-and-cycles
  (dolist (source
            '("function f(): int { 1 } function f(int x): int { x } true"
              "function f(int g): int { g } function g(): int { 1 } true"
              "function f(): int { 1 } let f = 2; true"
              "function f(): int { let f = 2; f } true"
              "function f(): int { 1 } if(false){var f = 1; true}else{true}"
              "function f(int x, int x): int { x } true"
              "function f(int x): int { x = 1; x } true"
              "function f(int x): int { let x = 1; x } true"
              "function f(int x): int { if(false){let x = 2; x}else{x} } true"
              "function f(): int { x } let x = 1; true"
              "function f(): int { let x = 1; x } function g(): int { x } true"
              "function f(int x): int { x } x == 1"
              "function f(): int { 1 } f = 2; true"
              "let f = 1; f() == 1" "missing()" "function f(): int { 1 } let saved = f; true"
              "function f(int x): int { x } f() == 1" "function f(int x): int { x } f(true) == 1"
              "function f(): int { true } true" "function f(): int { return true; } true"
              "function f(): int { if(true){return true;}else{1} } true"
              "function f(): int { if(1){return 1;}else{2} } true"
              "if(true){return true;}else{false}"
              "function f(): int { let x = if(true){return 1;}else{return 2;}; x } true"
              "function f(): int { (if(true){return 1;}else{return 2;}) + true } true"
              "function f(): int { if(if(true){return 1;}else{return 2;}){1}else{true} } true"
              "function f(): int { var n = 0; n = if(true){return 1;}else{return 2;}; true } true"
              "function f(): int { var n = 0; n = if(true){return 1;}else{return 2;}; missing } true"
              "function f(): int { f() } true"
              "function f(): int { g() } function g(): int { f() } true"
              "function f(): int { if(false){f()}else{1} } true"
              "function f(): int { var n = 1; n = if(true){return 1;}else{return 2;}; f() } true"
              "function f(): int { let x = x; x } true"
              "function unused(): int { 9223372036854775808 } true"))
    (v03-reject source "semantic")))

(deftest v04-call-runtime-order
  (dolist (pair '(("function f(int a, int b): int { 9223372036854775807 + 1 } f(1 / 0, 1 % 0) == 0" "division by zero")
                  ("function f(int a): int { 1 % 0 } f(1) == 0" "remainder by zero")
                  ("function f(): int { return 9223372036854775807 + 1; } f() == 0" "integer overflow")
                  ("function f(): int { 1 / 0 } let unused = f(); true" "division by zero")
                  ("function f(): int { 1 % 0 } function g(): int { f() + if(true){return 1;}else{return 2;} } g() == 0" "remainder by zero")))
    (v03-runtime (first pair) (second pair) t)))

(deftest v04-name-type-and-flow-boundaries
  (dolist (name '("Function" "Int" "Bool" "return1" "intValue" "bool1" "void" "never" "string"))
    (v03-positive (format nil "function ~A(): bool { true } ~A()" name name) :true)
    (v03-positive (format nil "function f(bool ~A): bool { ~A } f(true)" name name) :true)
    (v03-positive (format nil "let ~A = true; ~A" name name) :true))
  (dolist (name '("Int" "void" "never" "Unknown"))
    (v03-reject (format nil "function f(~A n): int { 1 } true" name) "parse")
    (v03-reject (format nil "function f(): ~A { 1 } true" name) "parse"))
  (dolist (text '("let int = 1; int == 1" "let bool = true; bool"
                  "function f(int x = 1): int { x } true" "function f(int x): int { x } f(x: 1) == 1"
                  "function f(): int { return 1 } true" "function f(): int { } true"))
    (v03-reject text "parse"))
  (dolist (text '("function f(int x): int { if(true){if(false){let x = 2; x}else{1}}else{1} } true"
                  "function f(int x): int { let y = if(true){let x = 2; x}else{1}; y } true"
                  "function a(): int { b() } function b(): int { c() } function c(): int { a() } true"
                  "function f(): int { 1 } f(1) == 1"
                  "function f(): int { var x = if(true){return 1;}else{return 2;}; x } true"
                  "function g(int a, int b): int { a + b } function f(): int { g(if(true){return 1;}else{return 2;}, true) } true"
                  "function f(): int { if(false){return false;}else{1} } true"))
    (v03-reject text "semantic"))
  (v03-positive "function f(bool stop): int { if(stop){return 3;}else{4} } f(true) + f(false) == 7" :true)
  (v03-positive "function f(int a, bool b, int c, bool d, int e, bool z, int g, bool h): bool { if(a == -9223372036854775808){if(b){if(c == 9223372036854775807){if(d){false}else{if(e == 3){if(z){if(g == -7){h == false}else{false}}else{false}}else{false}}}else{false}}else{false}}else{false} } f(-9223372036854775808, true, 9223372036854775807, false, 3, true, -7, false)" :true)
  (v03-runtime "function f(int a, int b): int { 1 / 0 } f(1, 1 % 0) == 0" "remainder by zero")
  (v03-runtime "function f(): int { g() } function g(): int { 1 / 0 } f() == 0" "division by zero")
  (v03-positive "function f(bool stop): int { if(stop){return 3;}else{1 / 0} } f(true) == 3" :true)
  (v03-runtime "function f(bool stop): int { if(stop){return 3;}else{1 / 0} } f(false) == 3" "division by zero"))
