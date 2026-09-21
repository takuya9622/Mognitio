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
      "var n = 0; loop { n = n + 1; if(n == 3){break;}; }; n == 3"
      "var n = 0; var total = 0; loop { n = n + 1; if(n < 3){continue;}; total = total + n; if(n == 5){break;}; }; total == 12"
      "var n = 0; var total = 0; loop { var local = 0; loop {local = local + 1; if(local == 2){break;}; }; total = total + local; n = n + 1; if(n == 3){break;}; }; total == 6"
      "let f = function(n: int): int { var i = 0; loop { i = i + 1; if(i == n){return i;}; } }; f(3) == 3"
      "let unused = function(): int { loop {} }; true"
      "let unused = function(): void { loop { continue; } }; true"
      "var n = 0; loop { let f = function(): void { loop {break;}; }; f(); n = n + 1; if(n == 2){break;}; }; n == 2"
      "var a = 1; var b = 2; var n = 0; loop { let old = a; a = b; b = old; n = n + 1; if(n == 3){break;}; }; a * 10 + b == 21"
      "var n = 0; loop { n = n + 1; if(n == 1000000){break;}; }; n == 1000000"))
    (v03-positive source :true))
  (dolist (source
    '("break; true" "continue; true" "loop { break; void }"
      "loop {continue; void}" "loop {true}" "loop {1}" "let x = loop {}; true"
      "loop {let f = function(): void {break;}; break;}; true"
      "loop {let f = function(): void {continue;}; break;}; true"
      "loop {if(true){break;}else{continue;}; void}; true"
      "loop {}; true" "loop {let x = 1; break;}; x == 1"
      "let f = function(): int { var n = 1; n = loop {}; true }; true"))
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
