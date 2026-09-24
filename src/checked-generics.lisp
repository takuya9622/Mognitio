(in-package #:mognitio.semantic)

(defun verify-generic-type-node (state node)
  ;; Rebuild symbolic fields and aliases from source under an independent scope.
  ;; The producer's declaration helper and stored template are not an oracle.
  (let* ((context (value-verification-context state)) (name (data-declaration-name node))
         (kind (data-declaration-kind node)) (id (value-context-next-template context))
         (template nil) (seen (make-hash-table :test #'equal)))
    (verification-ensure (null (gethash (token-text name) (value-context-names context))) "Duplicate verified template")
    (incf (value-context-next-template context))
    (call-with-type-parameters context (data-declaration-type-parameters node) (list :type id)
      (lambda (parameters)
        (setf template (make-generic-template :id id :declaration node :name (token-text name)
                         :parameters parameters :kind kind))
        (flet ((check-name (token)
                 (verification-ensure (not (gethash (token-text token) seen)) "Duplicate verified generic member")
                 (setf (gethash (token-text token) seen) t))
               (resolve (token)
                 (let ((type (resolve-type-token context token)))
                   (verification-ensure (not (nominal-type-p type :interface)) "Invalid generic storage") type)))
          (case kind
            (:alias (setf (generic-template-target template) (resolve-type-token context (data-declaration-target node))))
            (:struct
             (setf (generic-template-fields template)
                   (map 'list (lambda (member) (check-name (named-member-name member))
                                (cons (token-text (named-member-name member)) (resolve (named-member-value member))))
                        (data-declaration-members node))))
            (:enum
             (verification-ensure (plusp (length (data-declaration-members node))) "Empty verified generic enum")
             (setf (generic-template-variants template)
                   (loop for member across (data-declaration-members node) for index from 0
                         do (check-name (named-member-name member))
                         collect (make-variant-info :id index :name (token-text (named-member-name member))
                                   :types (map 'list #'resolve (named-member-value member))))))
            (otherwise (internal-error "Invalid generic declaration kind"))))))
    (let ((actual (gethash id (value-context-templates (checked-program-values (value-verification-checked state))))))
      (verification-ensure (and actual (equal (generic-template-shape template) (generic-template-shape actual)))
                           "Invalid generic template"))
    (setf (gethash id (value-context-templates context)) template
          (gethash (token-text name) (value-context-names context)) template)
    (verify-value-member state node :kind :type-template :index id)))
