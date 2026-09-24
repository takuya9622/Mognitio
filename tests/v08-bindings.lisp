(in-package #:mognitio.tests)

(deftest v08-explicit-local-boundaries
  (dolist (source '("let x: int = 42; var y: int = x; y=y+1; y==43"
                    "let f=function(x: int): int {x}; let alias=(f); alias(42)==42"
                    "let x: string = \"x\"; x==\"x\""
                    "let x: void = void; true"
                    "type E=enum { A(int); }; branch on (E::A(42)) {E::A(x)=>x==42,}"
                    "(branch when {true=>function():bool {true},else=>function():bool {false},})()"))
    (v07-accept source :true))
  (dolist (source '("let x=42; true" "var x=42; true" "let x: int=42; let copy=x; true"
                    "let x: bool=42; true" "let x: Unknown=42; true"
                    "let operation=branch when {true=>function():bool {true},else=>function():bool {false},}; operation()"
                    "var operation=function():bool {true}; true"
                    "let f=function():int{7}; let chosen={f}; chosen()==7"
                    "let f=function():int{7}; let chosen=loop {break f;}; chosen()==7"))
    (v03-reject source "semantic"))
  (let* ((checked (check-program (parse-text "let x: int=42; true")))
         (binding (aref (program-statements (checked-program-program checked)) 0)))
    (setf (mognitio.semantic::local-symbol-type (checked-symbol checked binding)) :bool)
    (signals internal-failure (verify-checked-program checked))))

(deftest v08-interface-annotated-locals
  (v07-accept "type Value=struct {n:int;}; interface I {let get=function():int;}
implement Value against I {let get=function():int {this->n};}
let x:I=Value {n:42}; var y:I=x; y=Value {n:43}; x->get()+y->get()==85" :true))
