(in-package #:mognitio.frontend)

(defun ascii-letter-p (character)
  (let ((code (char-code character)))
    (or (<= 65 code 90) (<= 97 code 122))))

(defun lex-source (source)
  (let ((text (source-text source)) (cursor 0)
        (tokens (make-array 0 :adjustable t :fill-pointer 0)))
    (labels ((emit (kind start end)
               (vector-push-extend
                (make-token :kind kind :span (make-span source start end)) tokens)))
      (loop while (< cursor (length text))
            for character = (char text cursor)
            do (cond
                 ((find character '(#\Space #\Tab #\Newline #\Return))
                  (incf cursor))
                 ((ascii-letter-p character)
                  (let ((start cursor))
                    (loop while (and (< cursor (length text))
                                     (ascii-letter-p (char text cursor)))
                          do (incf cursor))
                    (let* ((word (subseq text start cursor))
                           (kind (cdr (assoc word '(("true" . :true) ("false" . :false)
                                                    ("if" . :if) ("else" . :else))
                                             :test #'string=))))
                      (unless kind
                        (fail-at (make-span source start cursor) :lex "Unknown word"))
                      (emit kind start cursor))))
                 (t
                  (let ((kind (cdr (assoc character
                                         '((#\( . :left-paren) (#\) . :right-paren)
                                           (#\{ . :left-brace) (#\} . :right-brace))))))
                    (unless kind
                      (fail-at (make-span source cursor (1+ cursor))
                               :lex "Undefined character"))
                    (emit kind cursor (1+ cursor))
                    (incf cursor)))))
      (emit :eof cursor cursor))
    tokens))
