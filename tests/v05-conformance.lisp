(in-package #:mognitio.tests)

(deftest v05-keywords-and-source-shapes
  (let* ((words '("true" "false" "if" "else" "let" "var" "function" "return" "int" "bool"
                  "loop" "while" "break" "continue" "void"))
         (text (format nil "~{~A~^ ~}" words)) (tokens (lex-source (text-source text))))
    (same (append (mapcar (lambda (word) (intern (string-upcase word) :keyword)) words) '(:eof))
          (map 'list #'token-kind tokens))
    (loop for word in words for token across tokens do (same word (token-text token))))
  (dolist (word '("loop" "while" "break" "continue" "void"))
    (dolist (template '("let ~A = 1; true" "var ~A = 1; true" "let f = function(~A: int): int {1}; true"))
      (v03-reject (format nil template word) "parse")))
  (dolist (name '("Loop" "Void" "loopCount" "discard" "over" "as" "rec" "never"))
    (v03-positive (format nil "let ~A: bool = true; ~A" name name) :true))
  (dolist (space (list " " (string #\Tab) (string #\Return) (string #\Newline)))
    (let* ((text (format nil "-~A-1 == 1" space))
           (diag (diagnostic-of (lambda () (parse-text text)))))
      (same :parse (diagnostic-phase diag))
      (same (if (find #\Newline space) 2 (if (find #\Return space) 2 1)) (diagnostic-line diag))
      (v03-reject text "parse")))
  (v03-reject "let f = function(x: never): int {1}; true" "semantic")
  (dolist (text '("()" "let f = function(): void {return ();}; true" "loop {break ();}"
                  "(1,2) == 1"
                  "let f = function(x: function(): int): int {1}; true"
                  "let f = function(): void {return;}; f(,); true"))
    (v03-reject text "parse"))
  (let* ((program (parse-text "{ branch when{(true)=>{return;}}; }(void)"))
         (call (program-root program)) (block (call-expression-callee call))
         (if (expression-statement-expression (aref (sequence-node-statements block) 0))))
    (is (typep call 'call-expression)) (same nil (sequence-node-terminal block))
    (same 1 (length (branch-expression-arms if)))
    (same nil (return-statement-value (aref (sequence-node-statements (branch-arm-value (aref (branch-expression-arms if) 0))) 0)))
    (same 0 (span-start (node-span block))) (same 35 (span-end (node-span block)))))

(deftest v05-function-and-flow-contracts
  (dolist (source
    '("let f = ((function(x: int): int {x})); let a = ((f)); let b = a; let g = function(): int {b(7)}; g() == 7"
      "let f = function(left: int): int {left}; let g = function(right: int): int {right + 1}; (branch when{(false)=>{f},else=>{g}})(7) == 8"
      "let f = function(flag: bool): int {branch when{(flag)=>{loop {}},else=>{7}}}; f(false) == 7"
      "let f = function(): bool { let g = function(): bool {false}; g() }; f() == false"
      "let x: void = {var n: int = 0; n = 1;}; x; (void); {true}"
      "var i: int = 0; let answer: int = loop {i = i + 1; branch when{(i == 3)=>{break i * 10;}};}; answer == 30"
      "var checks: int=0; var runs: int=0; loop while({checks=checks+1; branch when{(checks<3)=>{continue;}}; checks<5}){runs=runs+1;}; branch when{(checks==5)=>{runs==2},else=>{false}}"
      "let double = function(value: int): int {value*2}; let inc = function(value: int): int {value+1}; var state: int=0; let result: int=(branch when{({state=1;true})=>{double},else=>{inc}})({state=state*10+2;3}); branch when{(result==6)=>{state==12},else=>{false}}"
      "let f = function(a: int,b: int): int {a+b}; let g = function(stop: bool): int {f(branch when{(stop)=>{return 7;},else=>{1}},1/0)}; g(true)==7"
      "let f = function(): int {loop {break {return 7;};}}; f()==7"
      "var n: int=0; loop while(n<1){n=n+1;}; n==1"
      "let f = function(a: void,b: bool,c: int,d: void,e: bool,fifth: int,g: void,h: int): void {a; d; g; branch when{(b)=>{branch when{(e)=>{return;}};}}; void}; f(void,true,3,{},false,5,void,8); true"))
    (v03-positive source :true))
  (v03-positive "loop {break false;}" :false)
  (dolist (source
    '("1()" "true()" "void()"
      "let f = function(): int {1}; f = f; true"
      "let f = function(): int {1}; f + 1 == 1"
      "let f = function(): int {1}; let g = function(x: int): int {x}; g(f)==1"
      "let f = function(): int {function(): int {1}}; true"
      "let f = function(): int {return function(): int {1};}; true"
      "let f = function(x: int,y: bool): int {x}; let g = function(x: bool,y: int): int {y}; let h=branch when{(true)=>{f},else=>{g}}; true"
      "let f = function(): int {let alias=f; alias()}; true"
      "let a=b; let b=a; true"
      "let f = function(): int {1}; let selected=loop {break f;}; let g=function(): int {selected()}; true"
      "let f=function(): void {branch when{(true)=>{return;},else=>{return;}}; void}; true"
      "loop {break; let x=1;}; true"
      "loop {continue; let x=1;}"
      "loop {branch when{(false)=>{break 1;},else=>{break true;}}}"
      "void < void" "branch when{(void)=>{true},else=>{false}}"))
    (v03-reject source "semantic"))
  (dolist (type '("int" "bool" "void"))
    (dolist (mutable '("let" "var"))
      (let ((value (cond ((equal type "int") "1") ((equal type "bool") "true") (t "void"))))
        (v03-reject (format nil "~A captured:~A=~A; let f=function(): ~A {captured}; true" mutable type value type) "semantic")
        (v03-reject (format nil "let outer=function(captured: ~A): ~A {let inner=function(): ~A {captured}; inner()}; true" type type type) "semantic"))))
  (dolist (index '(0 1 2))
    (v03-positive (format nil "let a=function(): int {10}; let b=function(): int {20}; let c=function(): int {30}; let n: int=~D; (branch when{(n==0)=>{a},else=>{branch when{(n==1)=>{b},else=>{c}}}})()==~D" index (* 10 (1+ index))) :true)))

(deftest v05-runtime-order-and-artifacts
  (dolist (pair
    '(("let f=function(x: int): int {1%0}; ({let bad: int=1/0; f})(9223372036854775807+1)==0" "division by zero")
      ("let f=function(a: int,b: int): int {1%0}; f(9223372036854775807+1,1/0)==0" "integer overflow")
      ("let f=function(a: int,b: int): int {1%0}; f(1,1/0)==0" "division by zero")
      ("let f=function(a: int,b: int): int {1%0}; f(1,2)==0" "remainder by zero")
      ("let f=function(a: int,b: int): int {a+b}; let g=function(stop: bool): int {f(branch when{(stop)=>{return 7;},else=>{1}},1/0)}; g(false)==7" "division by zero")
      ("var n: int=9223372036854775807; loop {n=n+1; break;}; true" "integer overflow")
      ("loop {let bad: int=1%0; break;}; true" "remainder by zero")))
    (v03-runtime (first pair) (second pair)))
  (check-native-relocation "let f=function(): void {}; var n: int=0; loop while(n<3){f(); n=n+1;}; n==3" :true)
  (check-native-relocation "let f=function(): int {1/0}; loop {break f();}==1" "division by zero"))

(deftest v05-large-mixed-void-call
  (v03-positive
    (with-output-to-string (out)
      (write-string "let f=function(" out)
      (dotimes (i 600)
        (when (plusp i) (write-string "," out))
        (format out "p~D: ~A" i (nth (mod i 3) '("void" "bool" "int"))))
      (write-string "): int {p0; branch when{(p1)=>{p599},else=>{0}}}; f(" out)
      (dotimes (i 600)
        (when (plusp i) (write-string "," out))
        (write-string (case (mod i 3) (0 "void") (1 "true") (2 (format nil "~D" i))) out))
      (write-string ")==599" out))
    :true))

(deftest v05-public-examples
  (dolist (path (directory (root-path "examples/*.mgn")))
    (v03-positive (uiop:read-file-string path :external-format :utf-8)
                  (if (equal (pathname-name path) "false") :false :true) t))
  (let ((text (uiop:read-file-string (root-path "README.md") :external-format :utf-8)) (cursor 0) (count 0))
    (loop for start = (search "```mgn" text :start2 cursor) while start do
      (let* ((body (+ start 6)) (end (search "```" text :start2 body)))
        (is end "Unclosed README example")
        (v03-positive (subseq text body end) :true t)
        (incf count) (setf cursor (+ end 3))))
    (same 5 count)))
