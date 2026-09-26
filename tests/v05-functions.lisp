(in-package #:mognitio.tests)

(deftest v05-function-values-and-scope
  (dolist (source
    '("let f :function(int):int= function(x: int): int { x + 1 }; let alias :function(int):int= ((f)); (alias)(2) == 3"
      "(function(x: int): int { x + 1 })(2) == 3"
      "let f :function(int):int= function(x: int): int { x + 1 }; let g :function(int):int= function(x: int): int { x - 1 }; (branch when{(false)=>{f},else=>{g}})(3) == 2"
      "let f :function():int= function(): int { 7 }; let alias :function():int= f; let g :function():int= function(): int { alias() }; g() == 7"
      "let f :function():int= function(): int { let g :function(int):int= function(x: int): int { x + 1 }; g(2) }; f() == 3"
      "let a :function():int= function(): int { 10 }; let b :function():int= function(): int { 20 }; (branch when{(true)=>{a},else=>{b}})() == 10"
      "let f :function(int):int= function(g: int): int { g }; let g :function():int= function(): int { 1 }; f(g()) == 1"
      "let add :function(int,int):int= function(a: int, b: int): int { a + b }; let sub :function(int,int):int= function(a: int, b: int): int { a - b }; var flag: bool = true; (branch when{(flag)=>{add},else=>{sub}})(10, branch when{(true)=>{flag = false; 3},else=>{0}}) == 13"))
    (v03-positive source :true))
  (dolist (source
    '("let x: int = 1; let f :function():int= function(): int { x }; true"
      "var x: int = 1; let f :function():int= function(): int { x }; true"
      "let outer :function(int):int= function(x: int): int { let inner :function():int= function(): int { x }; inner() }; true"
      "let f :function():int= function(): int { 1 }; let selected = branch when{(true)=>{f},else=>{f}}; let g :function():int= function(): int { selected() }; true"
      "let f :function():int= function(): int { 1 }; var alias :function():int= f; true"
      "let f :function():int= function(): int { 1 }; f == f"
      "let f :function():int= function(): int { 1 }; f()() == 1"
      "let f :function():int= function(): int { later() }; let later :function():int= function(): int { 1 }; true"
      "let f :function():int= function(): int { f() }; true"
      "let x :function(int):int= function(x: int): int { x }; true"
      "let f :function():int= function(): int { true }; true"
      "let f :function():int= function(): int { 1 }; let g :function():bool= function(): bool { true }; (branch when{(true)=>{f},else=>{g}})()"))
    (v03-reject source "semantic"))
  (v03-reject "function named(): int { 1 } true" "parse"))

(deftest v05-core-function-candidates
  (let* ((module (native-ir "let f :function():int= function(): int { 1 }; let g :function():int= function(): int { 2 }; (branch when{(true)=>{f},else=>{g}})() == 1"))
         (entry (first (mognitio.ir:module-functions module)))
         (call (loop for b in (mognitio.ir:ir-function-blocks entry)
                     thereis (find :call.value (mognitio.ir:basic-block-instructions b) :key #'mognitio.ir:instruction-op))))
    (same '(1 2) (sort (copy-list (second (mognitio.ir:instruction-value call))) #'<))
    (setf (mognitio.ir:ir-function-blocks entry) (reverse (mognitio.ir:ir-function-blocks entry)))
    (is (mognitio.ir:verify-module module))
    (setf (second (mognitio.ir:instruction-value call)) '(1))
    (signals internal-failure (mognitio.ir:verify-module module))))
