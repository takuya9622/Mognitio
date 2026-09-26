(in-package #:mognitio.tests)

(defun v05-nontermination (source)
  (let* ((path (put-text (fresh-path) source)) (artifact (build-text source)))
    (dolist (command (list (list (namestring (root-path "bin/mgn")) "run" (namestring path))
                           (list (namestring artifact))))
      (let* ((out (fresh-path ".stdout")) (err (fresh-path ".stderr"))
             (process (uiop:launch-program command :input nil :output out :error-output err)))
        (incf *processes*)
        (unwind-protect
             (progn (sleep 1) (is (uiop:process-alive-p process) "Expected bounded nontermination observation")
                    (same "" (uiop:read-file-string out)) (same "" (uiop:read-file-string err)))
          (when (uiop:process-alive-p process) (uiop:terminate-process process :urgent t))
          (uiop:wait-process process))))))

(deftest v05-unconditional-loops
  (dolist (source
    '("loop { break; }; true"
      "var n: int = 0; loop { n = n + 1; branch when{(n == 3)=>{break;}}; }; n == 3"
      "var n: int = 0; var total: int = 0; loop { n = n + 1; branch when{(n < 3)=>{continue;}}; total = total + n; branch when{(n == 5)=>{break;}}; }; total == 12"
      "var n: int = 0; var total: int = 0; loop { var local: int = 0; loop {local = local + 1; branch when{(local == 2)=>{break;}}; }; total = total + local; n = n + 1; branch when{(n == 3)=>{break;}}; }; total == 6"
      "let f :function(int):int= function(n: int): int { var i: int = 0; loop { i = i + 1; branch when{(i == n)=>{return i;}}; } }; f(3) == 3"
      "let unused :function():int= function(): int { loop {} }; true"
      "let unused :function():void= function(): void { loop { continue; } }; true"
      "var n: int = 0; loop { let f :function():void= function(): void { loop {break;}; }; f(); n = n + 1; branch when{(n == 2)=>{break;}}; }; n == 2"
      "var a: int = 1; var b: int = 2; var n: int = 0; loop { let old: int = a; a = b; b = old; n = n + 1; branch when{(n == 3)=>{break;}}; }; a * 10 + b == 21"
      "var n: int = 0; loop { n = n + 1; branch when{(n == 1000000)=>{break;}}; }; n == 1000000"))
    (v03-positive source :true))
  (dolist (source
    '("break; true" "continue; true" "loop { break; void }"
      "loop {continue; void}" "loop {true}" "loop {1}" "let x = loop {}; true"
      "loop {let f :function():void= function(): void {break;}; break;}; true"
      "loop {let f :function():void= function(): void {continue;}; break;}; true"
      "loop {branch when{(true)=>{break;},else=>{continue;}}; void}; true"
      "loop {}; true" "loop {let x: int = 1; break;}; x == 1"
      "let f :function():int= function(): int { var n: int = 1; n = loop {}; true }; true"))
    (v03-reject source "semantic"))
  (v05-nontermination "loop {}")
  (v05-nontermination "loop {continue;}"))

(deftest v05-loop-completion-boundary
  (let* ((checked (check-program (parse-text "loop { break; }; true")))
         (statement (aref (program-statements (checked-program-program checked)) 0))
         (loop (expression-statement-expression statement))
         (body (loop-expression-body loop))
         (break (aref (sequence-node-statements body) 0)))
    (same :void (checked-normal-type checked loop))
    (same nil (checked-normal-type checked body))
    (same '((:break 0 :void nil)) (completion-exits (checked-completion checked body)))
    (setf (gethash break (mognitio.semantic::checked-program-controls checked)) nil)
    (signals internal-failure (compile-program checked))
    (signals internal-failure (mognitio.ir:lower-program checked)))
  (let* ((module (native-ir "loop {}")) (blocks (entry-blocks module)))
    (same 2 (length blocks))
    (is (every (lambda (b) (eq :jump (first (mognitio.ir:basic-block-terminator b)))) blocks))))

(deftest v05-conditional-and-valued-loops
  (dolist (source
    '("var n: int = 0; loop while(n < 3){ n = n + 1; }; n == 3"
      "var n: int = 0; loop while(false){ n = n + 1; }; n == 0"
      "var n: int = 0; loop while({ n = n + 1; n < 3 }){}; n == 3"
      "var n: int = 0; loop while({ n = n + 1; branch when{(n < 3)=>{continue;}}; branch when{(n == 5)=>{break;}}; true }){}; n == 5"
      "var n: int = 0; var sum: int = 0; loop while(n < 5){ n = n + 1; branch when{(n < 3)=>{continue;}}; sum = sum + n; }; sum == 12"
      "let result: int = loop { break 7; }; result == 7"
      "loop {break true;}"
      "loop {break void;}; true"
      "let result: int = loop {let inner: int = loop {break 10;}; break inner + 1;}; result == 11"
      "let f :function():int= function(): int {1}; let g :function():int= function(): int {2}; (loop {branch when{(false)=>{break f;}}; break g;})() == 2"
      "let f :function(bool):int= function(stop: bool): int {let x: int = loop {break branch when{(stop)=>{return 7;},else=>{20}};}; x + 1}; f(true) + f(false) == 28"
      "let f :function():int= function(): int {loop while({return 7;}){break;}}; f() == 7"
      "let f :function():int= function(): int {loop {break {return 7;};}}; f() == 7"
      "let x: int = loop {break {break 9;};}; x == 9"
      "var i: int = 0; let x: int = loop {i = i + 1; break branch when{(i < 3)=>{continue;},else=>{30}};}; x == 30"
))
    (v03-positive source :true))
  (v03-positive "var i: int = 0; loop while({let local: int = i; i = i + 1; local < 3}){let local: void = void; local;}; i == 4" :true)
  (dolist (source
    '("loop while(1){}; true" "loop while(true){break 1;}; true"
      "loop while(false){break void;}; true"
      "let f :function():int= function(): int {loop while(true){break {return 1;};}}; true"
      "loop {branch when{(true)=>{break;}}; break void;}; true"
      "let f :function():int= function(): int {loop {branch when{(true)=>{break;}}; break {return 1;};}}; true"
      "loop {branch when{(true)=>{break 1;}}; break false;}"
      "loop {break function(): void {};}; true"
      "let f :function():int= function(): int {let x = loop while({return 7;}){break;}; x}; true"
      "let f :function():int= function(): int {loop while({return 7;}){break 1;}}; true"
      "loop while({let x: bool = true; x}){branch when{(x)=>{break;}};}; true"
      "loop while(x){let x = true;}; true"
      "loop while(false){missing;}; true"
      "loop while(true){true}; true"
      "let a :function():int= function(): int {1}; let b :function():bool= function(): bool {true}; let f = loop {branch when{(true)=>{break a;}}; break b;}; true"
      "let f :function():int= function(): int {loop while({return 1;}){let x = missing;}}; true"))
    (v03-reject source "semantic"))
  (dolist (source '("while(true){}" "loop true {}" "loop while true {}" "loop while(true) true"
                    "loop {continue 1;}" "break 1" "loop {};; true"))
    (v03-reject source "parse"))
  (v05-nontermination "loop while({continue;}){break;}")
  (v03-runtime "loop {break 1 / 0;} == 1" "division by zero"))

(deftest v05-condition-termination-has-no-false-exit
  (let* ((checked (check-program (parse-text "let f :function():int= function(): int {loop while({return 7;}){break;}}; f() == 7")))
         (function (signature-declaration (aref (checked-program-signatures checked) 1)))
         (loop (sequence-node-terminal (function-expression-body function)))
         (module (mognitio.ir:lower-program checked))
         (blocks (mognitio.ir:ir-function-blocks (second (mognitio.ir:module-functions module)))))
    (same nil (checked-normal-type checked loop))
    (same '((:return 1 nil nil)) (completion-exits (checked-completion checked loop)))
    (same 2 (length blocks))
    (same '(:jump :return) (mapcar (lambda (b) (first (mognitio.ir:basic-block-terminator b))) blocks))
    (is (mognitio.ir:verify-module module))))

(deftest v05-dispatch-call-loop-composite
  (dolist (pressure '(0 32 600))
    (v03-positive
     (with-output-to-string (out)
       (write-string "let add :function(int,int):int= function(a: int,b: int): int {a+b}; let sub :function(int,int):int= function(a: int,b: int): int {a-b}; let identity :function(int):int= function(value: int): int {value}; let base: int = 100; " out)
       (dotimes (i pressure) (format out "let saved~D: int = ~D; " i i))
       (write-string "var i:int=0; var total:int=0; var flip:bool=true; loop while(i<3){let value:int=(branch when{(flip)=>{add},else=>{sub}})(identity(base+i),{flip=branch when{(flip)=>{false},else=>{true}}; identity(i+1)}); total=total+value; i=i+1;}; branch when{(total==305)=>{" out)
       (dotimes (i pressure) (format out "saved~D + " i))
       (format out "base == ~D},else=>{false}}" (+ 100 (/ (* pressure (1- pressure)) 2))))
     :true)))

(deftest v05-condition-continue-has-no-exit
  (let* ((module (native-ir "loop while({continue;}){break;}")) (blocks (entry-blocks module)))
    (same 2 (length blocks))
    (is (every (lambda (b) (eq :jump (first (mognitio.ir:basic-block-terminator b)))) blocks))))
