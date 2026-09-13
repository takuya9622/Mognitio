(in-package #:mognitio.tests)

(deftest v03-equal-incoming-values
  ;; A shared incoming value can differ from the pre-branch binding.
  (dolist (condition '("true" "false"))
    (dolist (source
              (list
               (format nil "var a = 1; let b = 2; let result = if(~A){a = b; true}else{a = b; false}; a == 2" condition)
               (format nil "var a = false; let b = true; let result = if(~A){a = b; true}else{a = b; false}; a" condition)
               (format nil "var a = true; let b = false; let result = if(~A){a = b; true}else{a = b; false}; a == false" condition)
               ;; Equal incoming values coexist with a distinct-value merge.
               (format nil "var a = 1; var b = 2; var c = 10; let common = 3; let result = if(~A){a = common; b = common; c = 20; true}else{a = common; b = common; c = 30; false}; if(a == 3){if(b == 3){c == ~D}else{false}}else{false}"
                       condition (if (string= condition "true") 20 30))
               ;; Preserve the earlier operand while publishing the new binding.
               (format nil "var a = 1; let b = 2; let before = a + if(~A){a = b; 0}else{a = b; 0}; if(before == 1){a == 2}else{false}" condition)
               ;; Nested merges must propagate the common incoming value outward.
               (format nil "var a = 1; let b = 2; let result = if(~A){if(false){a = b; true}else{a = b; false}}else{a = b; true}; a == 2" condition)))
      (v03-positive source :true)))
  ;; Matching values need no extra block parameter, but later uses must resolve
  ;; to that value rather than the old environment entry.
  (let* ((ir (native-ir "var a = 1; let b = 2; let result = if(true){a = b; true}else{a = b; false}; a == b"))
         (join (find-if #'mognitio.ir:basic-block-parameters (mognitio.ir:module-blocks ir)))
         (comparison (find :eq (mognitio.ir:basic-block-instructions join)
                           :key #'mognitio.ir:instruction-op)))
    (same 1 (length (mognitio.ir:basic-block-parameters join)))
    (is comparison)
    (let ((args (mognitio.ir:instruction-operands comparison)))
      (same (first args) (second args)))))
