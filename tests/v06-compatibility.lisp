(in-package #:mognitio.tests)

;; Explicit v0.6 migration of three groups containing the formerly ordinary
;; identifier "string". Keep the historical fixture file unchanged. Every other
;; case in those groups is retained below; these replace, rather than skip,
;; the groups in the current-version suite. Reservation rejections live in
;; v06-postfix-and-static-contracts.
(eval-when (:load-toplevel :execute)
  (dolist (old '(v04-typed-functions-and-order v04-reserved-words-and-grammar
                 v04-name-type-and-flow-boundaries))
    (assert (member old *tests*))
    (setf *tests* (remove old *tests*))))

(deftest v06-migrated-typed-functions-and-order
  (dolist (source
            '("let subtotal :function(int,int):int= function(price: int, count: int): int { price * count }; let discounted :function(int):int= function(amount: int): int { amount - 20 }; discounted(subtotal(120, 3)) == 340"
              "let yes :function():bool= function(): bool { true }; let value :function():int= function(): int { 42 }; branch when{(yes())=>{value() == 42},else=>{false}}"
              "let later :function(int):int= function(n: int): int { n * 2 }; let first :function(int):int= function(n: int): int { later(n) + later(2) }; first(3) == 10"
              "let add :function(int,int):int= function(a: int, b: int): int { a + b }; add(add(1, 2), add(3, 4)) == 10"
              "let pair :function(int,int):int= function(a: int, b: int): int { a * 10 + b }; var n: int = 1; pair(n, branch when{(true)=>{n = 2; n},else=>{0}}) == 12"
              "let twice :function(int):int= function(n: int): int { n * 2 }; let left: int = 7; left + twice(twice(3)) + left == 26"
              "let update :function(int):int= function(n: int): int { var copy: int = n; copy = copy + 1; copy }; var n: int = 5; let a: int = update(n); let b: int = update(n); a + b + n == 17"
              "let a :function(int):int= function(n: int): int { let local: int = n; local }; let b :function(int):int= function(n: int): int { let local: int = n + 1; local }; let n: int = 8; let local: int = 2; a(local) + b(local) + n == 13"
              "let unused :function():int= function(): int { 1 / 0 }; true"
              "let main :function():int= function(): int { 7 }; false == false"
              "let Void :function(int):int= function(never: int): int { let text_name: int = never; text_name }; Void(3) == 3"
              "let Int :function(bool):bool= function(Bool: bool): bool { Bool }; let Function: bool = true; let return1: bool = false; let bool1: bool = true; Int(Function) == bool1"))
    (v03-positive source :true))
  (v03-positive "let no :function():bool= function(): bool { false }; no()" :false t)
  (v03-positive "let mixed :function(bool,int,bool,int,int,bool,int,bool):bool= function(a: bool, b: int, c: bool, d: int, e: int, f: bool, g: int, h: bool): bool { branch when{(a)=>{branch when{(c)=>{false},else=>{branch when{(f)=>{false},else=>{branch when{(h)=>{(b == -9223372036854775808) == (d == 9223372036854775807)},else=>{false}}}}}}},else=>{false}} }; mixed(true, -9223372036854775808, false, 9223372036854775807, 8, false, 9, true)" :true)
  (v03-positive
   (with-output-to-string (out)
     (loop for i from 23 downto 0 do (format out "let f~D:function(int):int=function(x: int): int { ~A }; " i
                            (if (= i 23) "x" (format nil "f~D(x) + 1" (1+ i)))))
     (write-string "f0(5) == 28" out)) :true))

(deftest v06-migrated-reserved-words-and-grammar
  (let* ((source (text-source "function return int bool Function Int Bool return1 intValue bool1 void never string"))
         (tokens (lex-source source)))
    (same '(:function :return :int :bool :identifier :identifier :identifier :identifier
            :identifier :identifier :void :identifier :string :eof)
          (map 'list #'token-kind tokens)))
  (dolist (word '("function" "return" "int" "bool"))
    (dolist (template '("let ~A = function(): int { 1 }; true" "let f :function(int):int= function(~A: int): int { 1 }; true"
                        "let ~A = 1; true" "var ~A = 1; true"))
      (v03-reject (format nil template word) "parse")))
  (dolist (source '("let f :function(never):int= function(n: never): int { 1 }; true"
                    "let f :function(Int):int= function(n: Int): int { n }; true" "let f :function():Unknown= function(): Unknown { 1 }; true"
                    "let f :function():int= function(): int { 1 }; f(1,) == 1"))
    (v03-reject source "semantic"))
  (v03-positive "let f :function(int):int= function(n: int,): int { n }; f(1,)==1" :true)
  (dolist (source '(
                    "let f = function(n): int { n }; true" "let f :function():int= function(): int; true"
                    "let f :function():int= function(): int { 1 };; true" "let f :function():int= function(): int { 1 };"






                    "let f :function():int= function(): int { branch when{(true)=>{return 1;}} 2 }; true"
                    "let f :function():int= function(): int { 1 + return 2 }; true" "return true;" "int(1) == 1"))
    (v03-reject source "parse")))

(deftest v06-migrated-name-type-and-flow-boundaries
  (dolist (name '("Function" "Int" "Bool" "return1" "intValue" "bool1" "Void" "never" "text_name"))
    (v03-positive (format nil "let ~A:function():bool=function(): bool { true }; ~A()" name name) :true)
    (v03-positive (format nil "let f :function(bool):bool= function(~A: bool): bool { ~A }; f(true)" name name) :true)
    (v03-positive (format nil "let ~A: bool = true; ~A" name name) :true))
  (dolist (name '("Int" "Void" "never" "Unknown"))
    (v03-reject (format nil "let f:function(~A):int=function(n: ~A): int { 1 }; true" name name) "semantic")
    (v03-reject (format nil "let f:function():~A=function(): ~A { 1 }; true" name name) "semantic"))
  (dolist (text '("let int = 1; int == 1" "let bool = true; bool"
                  "let f :function(int=1):int= function(x: int = 1): int { x }; true" "let f :function(int):int= function(x: int): int { x }; f(x: 1) == 1"
                  "let f :function():int= function(): int { return 1 }; true" ))
    (v03-reject text "parse"))
  (dolist (text '("let f :function(int):int= function(x: int): int { branch when{(true)=>{branch when{(false)=>{let x = 2; x},else=>{1}}},else=>{1}} }; true"
                  "let f :function(int):int= function(x: int): int { let y = branch when{(true)=>{let x = 2; x},else=>{1}}; y }; true"
                  "let a :function():int= function(): int { b() }; let b :function():int= function(): int { c() }; let c :function():int= function(): int { a() }; true"
                  "let f :function():int= function(): int { 1 }; f(1) == 1"
                  "let f :function():int= function(): int { var x = branch when{(true)=>{return 1;},else=>{return 2;}}; x }; true"
                  "let g :function(int,int):int= function(a: int, b: int): int { a + b }; let f :function():int= function(): int { g(branch when{(true)=>{return 1;},else=>{return 2;}}, true) }; true"
                  "let f :function():int= function(): int { branch when{(false)=>{return false;},else=>{1}} }; true"))
    (v03-reject text "semantic"))
  (v03-positive "let f :function(bool):int= function(stop: bool): int { branch when{(stop)=>{return 3;},else=>{4}} }; f(true) + f(false) == 7" :true)
  (v03-positive "let f :function(int,bool,int,bool,int,bool,int,bool):bool= function(a: int, b: bool, c: int, d: bool, e: int, z: bool, g: int, h: bool): bool { branch when{(a == -9223372036854775808)=>{branch when{(b)=>{branch when{(c == 9223372036854775807)=>{branch when{(d)=>{false},else=>{branch when{(e == 3)=>{branch when{(z)=>{branch when{(g == -7)=>{h == false},else=>{false}}},else=>{false}}},else=>{false}}}}},else=>{false}}},else=>{false}}},else=>{false}} }; f(-9223372036854775808, true, 9223372036854775807, false, 3, true, -7, false)" :true)
  (v03-runtime "let f :function(int,int):int= function(a: int, b: int): int { 1 / 0 }; f(1, 1 % 0) == 0" "remainder by zero")
  (v03-runtime "let g :function():int= function(): int { 1 / 0 }; let f :function():int= function(): int { g() }; f() == 0" "division by zero")
  (v03-positive "let f :function(bool):int= function(stop: bool): int { branch when{(stop)=>{return 3;},else=>{1 / 0}} }; f(true) == 3" :true)
  (v03-runtime "let f :function(bool):int= function(stop: bool): int { branch when{(stop)=>{return 3;},else=>{1 / 0}} }; f(false) == 3" "division by zero"))
