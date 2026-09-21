(in-package #:mognitio.tests)

(defun v06-runtime-image (source &optional options)
  (let ((mognitio.native.runtime::*test-options* options))
    (native-image source)))
(defun v06-runtime-artifact (source &optional options)
  (let ((path (put-bytes (fresh-path ".elf") (v06-runtime-image source options))))
    (sb-posix:chmod (namestring path) #o700) path))
(defun v06-expect-native (source expected &optional options)
  (expect-artifact (v06-runtime-artifact source options) expected))

(deftest v06-native-text-and-flow
  ;; Fixed expectations and the scalar-list oracle predate the native runtime.
  (replacing (expect-source
               (lambda (source expected)
                 (v06-expect-native source expected '(:stress t :validate t))))
    (v06-host-text-and-flow))
  (replacing (compiled-result
               (lambda (source)
                 (v06-expect-native source :true '(:stress t :validate t)) :true))
    (v06-host-independent-scalar-oracle)))

(deftest v06-native-text-failures
  (dolist (pair '(("\"a\"->slice(-1,0)==\"\"" "string_index_out_of_bounds")
                  ("\"a\"->slice(1,0)==\"\"" "string_index_out_of_bounds")
                  ("\"a\"->slice(0,2)==\"\"" "string_index_out_of_bounds")
                  ("\"a\"->slice(0,-1)==\"\"" "string_index_out_of_bounds")
                  ("\"a\"->slice(-1,1/0)==\"\"" "division by zero")
                  ("(\"a\"->slice(0,2)+{let bad=1/0;\"x\"})==\"\"" "string_index_out_of_bounds")))
    (multiple-value-bind (out err code) (process-result (list (namestring (build-text (first pair)))))
      (same 4 code) (same "" out) (same (format nil "runtime: ~A~%" (second pair)) err)))
  (dolist (options '((:mmap-fail t) (:arena-unit 65536 :cap 65536)))
    (let* ((source (if (getf options :mmap-fail)
                       "let unused=\"a\"+\"b\"; let later=1/0; true"
                       "var s=\"x\"; var i=0; loop while(i<20){s=s+s; i=i+1;}; s==\"x\""))
           (path (v06-runtime-artifact source options)))
      (multiple-value-bind (out err code) (process-result (list (namestring path)))
        (same 4 code) (same "" out) (same (format nil "runtime: allocation_failed~%") err)))))

(deftest v06-native-text-live-roots
  (dolist (source
    '("let f=function(s:string):string{s+\"!\"}; let a=f(\"A\"); let b=f(\"B\"); let c=f(\"C\"); let d=f(\"D\"); let e=f(\"E\"); let g=f(\"G\"); let h=f(\"H\"); a+b+c+d+e+g+h==\"A!B!C!D!E!G!H!\""
      "let f=function(s:string):string{s+\"!\"}; (f(\"abc\")->slice({let x=f(\"other\");1},{let y=f(\"value\");3}))+f(\"z\")==\"bcz!\""
      "let f=function(s:string):string{s+\"!\"}; let g=function(a:string,b:string,c:string):string{a+b+c}; g(f(\"a\"),f(\"b\"),f(\"c\"))==\"a!b!c!\""
      "let f=function(s:string):string{s+\"!\"}; var s=f(\"abc\"); let old=s->slice({s=f(\"z\");1},3); old==\"bc\""
      "let f=function(s:string):string{s+\"!\"}; var i=0; var s=\"\"; loop while(i<200){s=(loop {let x=f(s); break x;}); i=i+1;}; s->length()==200"
      "let f=function(s:string):string{s+\"!\"}; let g=function(s:string):string{s+\"?\"}; let h=if(true){f}else{g}; let a=h(\"a\"); h(a)==\"a!!\""))
    (v06-expect-native source :true '(:stress t :validate t :arena-unit 65536 :cap 65536))))

(deftest v06-native-runtime-encoding
  (dolist (pair '(((:imm-reg :r9 -1) "49b9ffffffffffffffff")
                  ((:add-reg :r9 :r10) "4d01d1") ((:sub-reg :rsi :r8) "4c29c6")
                  ((:cmp-reg :r8 :rax) "4939c0") ((:and-imm :r9 -8) "4981e1f8ffffff")
                  ((:or-imm :rax 2) "4881c802000000") ((:shr-imm :r10 3) "49c1ea03")
                  ((:div-rcx) "48f7f1")))
    (same (hex-bytes (second pair)) (mognitio.amd64:encode (machine (first pair))))))
