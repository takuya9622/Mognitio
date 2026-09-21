(in-package #:mognitio.tests)

(deftest v06-host-text-and-flow
  (dolist (source
    '("\"\"->length()==0" "\"Aあ😀\"->length()==3" "\"A\\0B\"->length()==3"
      "\"\\01\"->length()==2" "\"${name};let{}\"==\"${name};let{}\""
      "\"a\"+\"あ😀\"==\"aあ😀\"" "\"\"+\"a\"==\"a\"" "\"a\"+\"\"==\"a\"" "\"\"+\"\"==\"\""
      "\"a\\0\"+\"あ😀\"==\"a\\0あ😀\"" "\"a\"!=\"A\"" "\"é\"!=\"é\""
      "\"é\"->length()==2" "\"aあ😀\\0b\"->slice(1,4)==\"あ😀\\0\""
      "\"abc\"->slice(0,3)==\"abc\"" "\"abc\"->slice(0,0)==\"\"" "\"abc\"->slice(3,3)==\"\""
      "var s=\"abc\"; let alias=s; s=\"z\"; alias==\"abc\""
      "var s=\"abc\"; let part=s->slice({s=\"z\";1},3); part==\"bc\""
      "var s=\"a\"; let result=s+{s=\"b\";s}; result==\"ab\""
      "var n=0; let s={n=n+1;\"abc\"}->slice({n=n*10+2;0},{n=n*10+3;1}); if(n==123){s==\"a\"}else{false}"
      "let f=function(x:string):string {x+\"!\"}; let g=function():string {f(\"あ\")}; g()==\"あ!\""
      "let f=function():int {({return 7;})->unknown(1/0)}; f()==7"
      "let f=function():int {\"abc\"->slice({return 7;},1/0)->length()}; f()==7"
      "let f=function():int {({return 7;})+\"a\"}; f()==7"
      "let v=loop {\"a\"->slice({break \"ok\";},1/0);}; v==\"ok\""
      "var i=0; loop while(i<3){i=i+1; \"a\"->slice({continue;},1/0);}; i==3"
      "if(true){true}else{\"a\"->slice(-1,9)==\"\"}"
      "let unused=function():string {\"a\"->slice(-1,9)}; true"
      "let length=1; let slice=2; let string_length=function(x:string):int{x->length()}; let measure=string_length; measure(\"aあ😀\"->slice(1,3))==2"
      "(if(true){\"abc\"}else{\"z\"})->slice(0,1)->length()==1"
      "(loop {break \"abc\";})->length()==3"))
    (expect-source source :true))
  (expect-source "\"a\"==\"A\"" :false)
  (expect-source "\"a\"!=\"a\"" :false)
  (let ((heading "let heading=function(source:string):string {let size=source->length(); var end=2; loop while(end<size){if(source->slice(end,end+1)==\"\\n\"){break;}; end=end+1;}; \"<h1>\"+source->slice(2,end)+\"</h1>\"}; "))
    (dolist (tail '("heading(\"# 題名😀\\n本文\")==\"<h1>題名😀</h1>\""
                    "heading(\"# 題名😀\")==\"<h1>題名😀</h1>\""
                    "heading(\"# \")==\"<h1></h1>\""))
      (expect-source (concatenate 'string heading tail) :true))))

(deftest v06-host-runtime-failures
  (dolist (pair '(("\"a\"->slice(-1,0)==\"\"" "string_index_out_of_bounds")
                  ("\"a\"->slice(1,0)==\"\"" "string_index_out_of_bounds")
                  ("\"a\"->slice(0,2)==\"\"" "string_index_out_of_bounds")
                  ("\"a\"->slice(-1,1/0)==\"\"" "division by zero")
                  ("\"a\"->slice(0,1/0)==\"\"" "division by zero")
                  ("(\"a\"->slice(0,2)+{let bad=1/0;\"x\"})==\"\"" "string_index_out_of_bounds")))
    (let* ((path (put-text (fresh-path) (first pair)))
           (err (expect-cli (list "run" (namestring path)) 4)))
      (is (search (second pair) err))))
  (same mognitio.integer:+maximum+ (mognitio.text:checked-size (1- mognitio.integer:+maximum+) 1))
  (handler-case (progn (mognitio.text:checked-size mognitio.integer:+maximum+ 1) (is nil))
    (mognitio.runtime:program-runtime-failure (c) (same :string-size-overflow (mognitio.runtime:failure-kind c))))
  (let ((compiled (compile-program (v06-checked "(\"a\"+\"b\")==\"ab\""))))
    (replacing (mognitio.text::allocate-bytes (lambda (size) (declare (ignore size)) (error 'storage-condition)))
      (handler-case (progn (execute-program compiled) (is nil))
        (mognitio.runtime:program-runtime-failure (c) (same :allocation-failed (mognitio.runtime:failure-kind c)))))
    (replacing (mognitio.text::allocate-bytes (lambda (size) (declare (ignore size)) (error "Unexpected bug")))
      (signals internal-failure (execute-program compiled)))))

(defun v06-source-literal (scalars)
  ;; Independent scalar-list oracle. Never calls the production decoder.
  (with-output-to-string (out)
    (write-char #\" out)
    (dolist (scalar scalars)
      (case scalar
        (0 (write-string "\\0" out)) (9 (write-string "\\t" out))
        (10 (write-string "\\n" out)) (13 (write-string "\\r" out))
        (34 (write-string "\\\"" out)) (92 (write-string "\\\\" out))
        (otherwise (write-char (code-char scalar) out))))
    (write-char #\" out)))

(deftest v06-host-independent-scalar-oracle
  (let ((seed 601) (alphabet '(0 9 10 13 34 65 92 233 769 12354 128512 1114111)))
    (labels ((next (n) (setf seed (mod (+ (* seed 1664525) 1013904223) (expt 2 32))) (mod seed n))
             (sample () (loop repeat (next 12) collect (nth (next (length alphabet)) alphabet))))
      (dotimes (i 60)
        (let* ((a (sample)) (b (sample)) (joined (append a b)) (start (next (1+ (length joined))))
               (end (+ start (next (1+ (- (length joined) start)))))
               (source (format nil "let s=~A+~A; if(s->length()==~D){s->slice(~D,~D)==~A}else{false}"
                               (v06-source-literal a) (v06-source-literal b) (length joined) start end
                               (v06-source-literal (subseq joined start end)))))
          (same :true (compiled-result source)))))))

(deftest v06-host-copy-and-gc-survival
  (let* ((p (token-payload (aref (lex-source (text-source "\"Aあ😀\"")) 0)))
         (value (mognitio.text:literal-value p))
         (empty (mognitio.text:literal-value (make-text-payload :octets (make-array 0 :element-type '(unsigned-byte 8)) :scalar-count 0)))
         (copy (mognitio.text:text-slice value 0 3)))
    (is (not (eq value copy))) (is (mognitio.text:text-equal value copy))
    (is (not (eq value (mognitio.text:text-concat empty value))))
    (is (not (eq value (mognitio.text:text-concat value empty)))))
  (let ((original (fdefinition 'mognitio.text::allocate-bytes)) (allocations 0))
    (replacing (mognitio.text::allocate-bytes
                 (lambda (size) (incf allocations) (sb-ext:gc :full t) (funcall original size)))
      (same :true (compiled-result "let f=function(s:string):string {s+\"!\"}; let a=f(\"A\"); let b=f(\"B\"); let c=f(\"C\"); var carry=\"\"; var i=0; loop while(i<5){carry=f(carry); i=i+1;}; if(a+b+c==\"A!B!C!\"){carry==\"!!!!!\"}else{false}"))
      (same :true (compiled-result "let f=function(s:string):string {s+\"!\"}; (f(\"abc\")->slice({let x=f(\"other\");1},{let y=f(\"value\");3}))+f(\"z\")==\"bcz!\"")))
    (is (> allocations 10))))


(deftest v06-host-bounded-reclamation
  (multiple-value-bind (out err code)
      (process-result (list "sbcl" "--dynamic-space-size" "256" "--noinform" "--script"
                            (namestring (root-path "tests/v06-host-gc-entry.lisp"))) :timeout 120)
    (same 0 code) (same "" err)
    (is (search "HOST_GC_OK heap=268435456" out))
    (is (search "allocations=9001 bytes=1179779072 dead=9001 held=3" out))))

(deftest v06-host-fault-processes
  (let ((path (put-text (fresh-path) "let unused=\"a\"+\"b\"; let later=1/0; true")))
    (dolist (test '(("allocation" 4 "allocation_failed") ("size" 4 "string_size_overflow")
                    ("compiler" 3 "internal")))
      (multiple-value-bind (out err code)
          (process-result (list "sbcl" "--noinform" "--script"
                                (namestring (root-path "tests/v06-host-fault-entry.lisp"))
                                (first test) (namestring path)))
        (same (second test) code) (same "" out) (same 1 (count #\Newline err))
        (is (search (third test) err))
        (is (not (search "division by zero" err)))))))


(deftest v06-diagnostic-storage-failures
  (let ((path (put-text (fresh-path) "let unused=\"a\"+\"b\"; let later=1/0; true")))
    (dolist (pair '(("allocation-report" 4) ("compiler-report" 3) ("source-report" 3)))
      (multiple-value-bind (out err code)
          (process-result (list "sbcl" "--noinform" "--script"
                                (namestring (root-path "tests/v06-host-fault-entry.lisp"))
                                (first pair) (namestring path)))
        (same (second pair) code) (same "" out) (same "" err)))))

(deftest v06-concat-independent-size-boundaries
  ;; Impossible metadata is test-only, and must fail before allocation/copy.
  (let* ((bytes (make-array 1 :element-type '(unsigned-byte 8) :initial-element 65))
         (left (mognitio.text::%make-text-value bytes mognitio.integer:+maximum+))
         (right (mognitio.text::%make-text-value bytes 1)) (allocated nil))
    (replacing (mognitio.text::allocate-text
                 (lambda (&rest args) (declare (ignore args)) (setf allocated t) (error "Unexpected allocation")))
      (handler-case (progn (mognitio.text:text-concat left right) (is nil))
        (mognitio.runtime:program-runtime-failure (c)
          (same :string-size-overflow (mognitio.runtime:failure-kind c)))))
    (same nil allocated)
    (let ((boundary (mognitio.text:text-concat
                     (mognitio.text::%make-text-value bytes (1- mognitio.integer:+maximum+)) right)))
      (same mognitio.integer:+maximum+ (mognitio.text:text-length boundary))
      (same #(65 65) (mognitio.text:text-value-octets boundary)))))
