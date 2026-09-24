(in-package #:mognitio.tests)

(defun v06-native-ir (source)
  (handler-case (native-ir source)
    (compiler-failure (c)
      (error "Core fixture ~S: ~A" source (diagnostic-message (failure-diagnostic c))))))

(defun v06-core-instructions (module)
  (loop for function in (mognitio.ir:module-functions module) append
    (loop for b in (mognitio.ir:ir-function-blocks function) append (mognitio.ir:basic-block-instructions b))))
(defun v06-core-op (module op)
  (find op (v06-core-instructions module) :key #'mognitio.ir:instruction-op))
(defun v06-core-snapshot (module)
  (list (loop for p across (mognitio.ir:module-literal-pool module)
              collect (list (text-payload-octets p) (text-payload-scalar-count p)))
        (loop for f in (mognitio.ir:module-functions module) collect
          (loop for b in (mognitio.ir:ir-function-blocks f) collect
            (list (mognitio.ir:basic-block-id b) (mognitio.ir:basic-block-parameters b)
                  (loop for i in (mognitio.ir:basic-block-instructions b) collect
                    (list (mognitio.ir:instruction-result i) (mognitio.ir:instruction-type i)
                          (mognitio.ir:instruction-op i) (mognitio.ir:instruction-value i)
                          (mognitio.ir:instruction-operands i) (mognitio.ir:instruction-effects i)))
                  (mognitio.ir:basic-block-terminator b))))))

(deftest v06-core-text-lowering
  (let* ((source "let f=function(s:string):string{s->slice(0,1)+\"\"}; let x: string=\"日本\"; let y: string=f(x); let unused: bool=x!=y; y->length()==1")
         (module (v06-native-ir source)))
    (is (mognitio.ir:verify-module module))
    (same (v06-core-snapshot module) (v06-core-snapshot (v06-native-ir source)))
    (dolist (op '(:const.text :text.slice :text.concat :text.not-equal :text.length :call.value))
      (is (v06-core-op module op)))
    (same '(:string) (mognitio.ir:ir-function-parameter-types (second (mognitio.ir:module-functions module))))
    (same :string (mognitio.ir:ir-function-result-type (second (mognitio.ir:module-functions module))))
    (same 2 (length (mognitio.ir:module-literal-pool module))))
  (let* ((module (v06-native-ir "let a: string=\"x\"; let b: string=\"x\"; let unused: string=\"\"+\"\"; a==b"))
         (literals (remove-if-not (lambda (i) (eq :const.text (mognitio.ir:instruction-op i)))
                                  (v06-core-instructions module))))
    (same '(1 1 0 0) (mapcar #'mognitio.ir:instruction-value literals))
    (same 2 (length (mognitio.ir:module-literal-pool module)))
    ;; Even an unused empty concat retains its allocation/failure operation.
    (is (v06-core-op module :text.concat)))
  (let ((module (v06-native-ir "branch when{(false)=>{let bad: string=\"a\"->slice(9,10); false},else=>{true}}")))
    (is (mognitio.ir:verify-module module))
    (is (not (find :text.slice (mognitio.ir:basic-block-instructions (first (entry-blocks module)))
                   :key #'mognitio.ir:instruction-op)))
    (is (v06-core-op module :text.slice)))
  (dolist (source '("let f=function():bool{\"x\"->slice({return true;},0)}; f()"
                    "let f=function():bool{({return true;})->whatever(\"x\"+\"y\")}; f()"
                    "let f=function():bool{\"x\"+{return true;}}; f()"))
    (let ((module (v06-native-ir source)))
      (is (mognitio.ir:verify-module module))
      (same nil (v06-core-op module :text.slice))
      (same nil (v06-core-op module :text.concat)))))

(deftest v06-core-text-corruption
  (dolist (mutate
           (list
            (lambda (m) (setf (mognitio.ir:instruction-type (v06-core-op m :text.concat)) :int))
            (lambda (m) (setf (mognitio.ir:instruction-operands (v06-core-op m :text.concat)) nil))
            (lambda (m) (setf (mognitio.ir:instruction-effects (v06-core-op m :text.concat)) nil))
            (lambda (m) (setf (mognitio.ir:instruction-effects (v06-core-op m :text.length)) '(:may-allocate)))
            (lambda (m) (setf (mognitio.ir:instruction-effects (v06-core-op m :const.text)) '(:may-fail)))
            (lambda (m) (setf (mognitio.ir:instruction-value (v06-core-op m :const.text)) 999))
            (lambda (m) (setf (mognitio.ir:instruction-value (v06-core-op m :const.text)) -1))
            (lambda (m) (setf (mognitio.ir:instruction-value (v06-core-op m :const.text)) 0.0))
            (lambda (m) (setf (mognitio.ir:instruction-type (v06-core-op m :const.text)) :int))
            (lambda (m) (setf (mognitio.ir:module-literal-pool m) '(bad)))
            (lambda (m) (setf (aref (mognitio.ir:module-literal-pool m) 0)
                              (make-text-payload :octets (hex-bytes "61") :scalar-count 2)))
            (lambda (m) (setf (aref (mognitio.ir:module-literal-pool m) 0)
                              (make-text-payload :octets (hex-bytes "c080") :scalar-count 1)))
            (lambda (m) (setf (aref (mognitio.ir:module-literal-pool m) 0)
                              (make-text-payload :octets #(65) :scalar-count 1)))
            (lambda (m) (setf (mognitio.ir:instruction-operands (v06-core-op m :text.concat))
                              (list (mognitio.ir:instruction-result (v06-core-op m :constant))
                                    (mognitio.ir:instruction-result (v06-core-op m :const.text)))))))
    (let ((module (v06-native-ir "let n: int=1; let s: string=\"a\"+\"b\"; s->length()==n")))
      (funcall mutate module)
      (signals internal-failure (mognitio.ir:verify-module module))))
  (let ((module (v06-native-ir "let f=function(s:string):string{s}; f(\"x\")==\"x\"")))
    (setf (mognitio.ir:instruction-effects (v06-core-op module :call.value)) '(:call-barrier))
    (signals internal-failure (mognitio.ir:verify-module module))))

(defun v06-evaluate-core (module)
  ;; A test interpreter using host character sequences, not text runtime helpers.
  ;; It checks lowering independently of the host-form backend and root producer.
  (let ((budget 10000))
    (labels ((invoke (id arguments)
               (let* ((function (find id (mognitio.ir:module-functions module) :key #'mognitio.ir:ir-function-id))
                      (values (make-hash-table)) (block-id (mognitio.ir:ir-function-entry function))
                      (incoming arguments))
                 (labels ((value (id) (multiple-value-bind (v found) (gethash id values)
                                       (unless found (error "Undefined test interpreter value")) v)))
                   (loop
                     (when (minusp (decf budget)) (error "Core interpreter budget exhausted"))
                     (let ((block (find block-id (mognitio.ir:ir-function-blocks function) :key #'mognitio.ir:basic-block-id)))
                       (loop for p in (mognitio.ir:basic-block-parameters block) for arg in incoming do
                         (setf (gethash (car p) values) arg))
                       (dolist (i (mognitio.ir:basic-block-instructions block))
                         (let* ((args (mapcar #'value (mognitio.ir:instruction-operands i)))
                                (a (first args)) (b (second args))
                                (result
                                  (case (mognitio.ir:instruction-op i)
                                    ((:constant :function) (mognitio.ir:instruction-value i))
                                    (:const.text (sb-ext:octets-to-string
                                                  (text-payload-octets (aref (mognitio.ir:module-literal-pool module)
                                                                            (mognitio.ir:instruction-value i)))
                                                  :external-format :utf-8))
                                    (:text.concat (concatenate 'string a b))
                                    (:text.length (length a))
                                    (:text.slice (subseq a b (third args)))
                                    (:text.equal (if (string= a b) 1 0))
                                    (:text.not-equal (if (string/= a b) 1 0))
                                    (:call.value (invoke a (rest args)))
                                    (:call (invoke (mognitio.ir:instruction-value i) args))
                                    (:neg (- a)) (:add (+ a b)) (:sub (- a b)) (:mul (* a b))
                                    (:eq (if (= a b) 1 0)) (:ne (if (/= a b) 1 0))
                                    (:lt (if (< a b) 1 0)) (:le (if (<= a b) 1 0))
                                    (:gt (if (> a b) 1 0)) (:ge (if (>= a b) 1 0))
                                    (otherwise (error "Unhandled test interpreter operation")))))
                           (setf (gethash (mognitio.ir:instruction-result i) values) result)))
                       (let ((term (mognitio.ir:basic-block-terminator block)))
                         (ecase (first term)
                           (:return (return (value (second term))))
                           (:branch (setf block-id (if (zerop (value (second term))) (fourth term) (third term)) incoming nil))
                           (:jump (setf incoming (mapcar #'value (third term)) block-id (second term)))))))))))
      (invoke 0 nil))))

(deftest v06-core-ordered-execution
  (dolist (source
            '("var s: string=\"abc\"; s->slice({s=\"z\"; 0},1)==\"a\""
              "var s: string=\"a\"; s+{s=\"b\"; s}==\"ab\""
              "let f=function(a:string,b:string):string{a+b}; f(\"先\"+\"行\",\"後\"+\"続\")==\"先行後続\""
              "let a=function(s:string):string{s+\"a\"}; let b=function(s:string):string{s+\"b\"}; var choose: bool=true; (branch when{(choose)=>{a},else=>{b}})({choose=false; \"x\"})==\"xa\""
              "var s: string=\"a\"; let r: string=loop {s=s+\"b\"; branch when{(s->length()<3)=>{continue;}}; break s;}; r==\"abb\""
              "var s: string=\"a\"; loop while(s->length()<5){s=s+\"b\";}; s==\"abbbb\""
              "let f=function():string{\"x\"->slice({return \"ok\";},0)}; f()==\"ok\""
              "let r: string=loop {\"x\"->slice({break \"ok\";},0);}; r==\"ok\""
              "var n: int=0; loop while(n<2){n=n+1; \"x\"->slice({continue;},0);}; n==2"
              "let a: string=branch when{(true)=>{\"x\"+\"y\"},else=>{\"z\"}}; a==\"xy\""
              "branch when{(false)=>{let bad: string=\"a\"->slice(9,10); false},else=>{true}}"
              "\"a\\0日\"->slice(1,3)==\"\\0日\""))
    (let ((module (v06-native-ir source)))
      (is (mognitio.ir:verify-module module))
      (is (mognitio.roots:analyze-roots module))
      (same 1 (v06-evaluate-core module))))
  (loop for count from 0 to 20 do
    (let* ((source (format nil "var s: string=\"日\"; var i: int=0; loop while(i<~D){s=s+\"本\"; i=i+1;}; s==\"日~A\""
                           count (make-string count :initial-element #\本)))
           (module (v06-native-ir source)))
      (is (mognitio.roots:analyze-roots module))
      (same 1 (v06-evaluate-core module)))))

(deftest v06-core-operation-contracts
  (let ((source "let n: int=0; let s: string=\"ab\"; let a: string=s->slice(n,1); let b: string=a+\"x\"; let c: bool=b!=s; let d: bool=b==s; a->length()==1"))
    (dolist (op '(:const.text :text.slice :text.concat :text.not-equal :text.equal :text.length))
      (dolist (corruption '(:result :arity :operand :effect))
        (let* ((module (v06-native-ir source)) (inst (v06-core-op module op)))
          (ecase corruption
            (:result (setf (mognitio.ir:instruction-type inst) :void))
            (:arity (push 0 (mognitio.ir:instruction-operands inst)))
            (:operand (if (eq op :const.text)
                          (setf (mognitio.ir:instruction-value inst) nil)
                          (setf (first (mognitio.ir:instruction-operands inst)) 0)))
            (:effect (push :unknown (mognitio.ir:instruction-effects inst))))
          (signals internal-failure (mognitio.ir:verify-module module)))))))

(deftest v06-literal-pool-source-order
  (dolist (source '("true" "\"x\"==\"x\""))
    (let ((pool (mognitio.ir:module-literal-pool (v06-native-ir source))))
      (same 0 (length (text-payload-octets (aref pool 0))))
      (same 0 (text-payload-scalar-count (aref pool 0)))))
  (let* ((module (v06-native-ir "let f=function():string{let nested=function():string{\"first\"}; \"second\"}; let unused: string=\"third\"; f()==\"second\""))
         (pool (mognitio.ir:module-literal-pool module)))
    (same '("" "first" "second" "third")
          (loop for p across pool collect (sb-ext:octets-to-string (text-payload-octets p) :external-format :utf-8)))
    (is (mognitio.ir:verify-module module)))
  (dolist (pool (list #() (vector (make-text-payload :octets (hex-bytes "61") :scalar-count 1))
                     (vector (make-text-payload :octets (hex-bytes "") :scalar-count 0)
                             (make-text-payload :octets (hex-bytes "") :scalar-count 0))))
    (let ((module (v06-native-ir "true")))
      (setf (mognitio.ir:module-literal-pool module) pool)
      (signals internal-failure (mognitio.ir:verify-module module)))))
