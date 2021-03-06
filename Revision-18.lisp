;;; -*- Mode: Lisp; Syntax: Common-Lisp; Package: ("CONDITIONS" :USE "LISP" :SHADOW ("BREAK" "ERROR" "CERROR" "WARN" "CHECK-TYPE" "ASSERT" "ETYPECASE" "CTYPECASE" "ECASE" "CCASE")); Base: 10 -*-
;;;
;;; CONDITIONS
;;;
;;; This is a sample implementation. It is not in any way intended as the definition
;;; of any aspect of the condition system. It is simply an existence proof that the
;;; condition system can be implemented.
;;;
;;; While this written to be "portable", this is not a portable condition system
;;; in that loading this file will not redefine your condition system. Loading this
;;; file will define a bunch of functions which work like a condition system. Redefining
;;; existing condition systems is beyond the goal of this implementation attempt.

(IN-PACKAGE "CONDITIONS" :USE '("LISP"))
(SHADOW '(BREAK ERROR CERROR WARN CHECK-TYPE ASSERT ETYPECASE
	  CTYPECASE ECASE CCASE))
(EXPORT '(;; Shadowed symbols
	  BREAK ERROR CERROR WARN CHECK-TYPE ASSERT ETYPECASE
	  CTYPECASE ECASE CCASE
	  ;; New symbols
	  *BREAK-ON-SIGNALS* *DEBUGGER-HOOK* SIGNAL
	  HANDLER-CASE HANDLER-BIND IGNORE-ERRORS DEFINE-CONDITION MAKE-CONDITION
	  WITH-SIMPLE-RESTART RESTART-CASE RESTART-BIND RESTART-NAME
	  RESTART-NAME FIND-RESTART COMPUTE-RESTARTS INVOKE-RESTART
	  INVOKE-RESTART-INTERACTIVELY ABORT CONTINUE MUFFLE-WARNING
	  STORE-VALUE USE-VALUE INVOKE-DEBUGGER RESTART CONDITION
	  WARNING SERIOUS-CONDITION SIMPLE-CONDITION SIMPLE-WARNING SIMPLE-ERROR
	  SIMPLE-CONDITION-FORMAT-STRING SIMPLE-CONDITION-FORMAT-ARGUMENTS
	  STORAGE-CONDITION STACK-OVERFLOW STORAGE-EXHAUSTED TYPE-ERROR
	  TYPE-ERROR-DATUM TYPE-ERROR-EXPECTED-TYPE SIMPLE-TYPE-ERROR
	  PROGRAM-ERROR CONTROL-ERROR STREAM-ERROR STREAM-ERROR-STREAM
	  END-OF-FILE FILE-ERROR FILE-ERROR-PATHNAME CELL-ERROR
	  UNBOUND-VARIABLE UNDEFINED-FUNCTION ARITHMETIC-ERROR
	  ARITHMETIC-ERROR-OPERATION ARITHMETIC-ERROR-OPERANDS
	  PACKAGE-ERROR PACKAGE-ERROR-PACKAGE
	  DIVISION-BY-ZERO FLOATING-POINT-OVERFLOW FLOATING-POINT-UNDERFLOW))


(EVAL-WHEN (EVAL COMPILE LOAD)

(DEFVAR *THIS-PACKAGE* (FIND-PACKAGE "CONDITIONS"))

);NEHW-LAVE


;;; Unique Ids

(DEFVAR *UNIQUE-ID-TABLE* (MAKE-HASH-TABLE))
(DEFVAR *UNIQUE-ID-COUNT* -1)

(DEFUN UNIQUE-ID (OBJ)
  "Generates a unique integer ID for its argument."
  (OR (GETHASH OBJ *UNIQUE-ID-TABLE*)
      (SETF (GETHASH OBJ *UNIQUE-ID-TABLE*) (INCF *UNIQUE-ID-COUNT*))))

;;; Miscellaneous Utilities

(EVAL-WHEN (EVAL COMPILE LOAD)

(DEFUN PARSE-KEYWORD-PAIRS (LIST KEYS)
  (DO ((L LIST (CDDR L))
       (K '() (LIST* (CADR L) (CAR L) K)))
      ((OR (NULL L) (NOT (MEMBER (CAR L) KEYS)))
       (VALUES (NREVERSE K) L))))

(DEFMACRO WITH-KEYWORD-PAIRS ((NAMES EXPRESSION &OPTIONAL KEYWORDS-VAR) &BODY FORMS)
  (LET ((TEMP (MEMBER '&REST NAMES)))
    (UNLESS (= (LENGTH TEMP) 2) (ERROR "&REST keyword is ~:[missing~;misplaced~]." TEMP))
    (LET ((KEY-VARS (LDIFF NAMES TEMP))
          (KEY-VAR (OR KEYWORDS-VAR (GENSYM)))
          (REST-VAR (CADR TEMP)))
      (LET ((KEYWORDS (MAPCAR #'(LAMBDA (X) (INTERN (STRING X) (FIND-PACKAGE "KEYWORD")))
			      KEY-VARS)))
        `(MULTIPLE-VALUE-BIND (,KEY-VAR ,REST-VAR)
             (PARSE-KEYWORD-PAIRS ,EXPRESSION ',KEYWORDS)
           (LET ,(MAPCAR #'(LAMBDA (VAR KEYWORD) `(,VAR (GETF ,KEY-VAR ,KEYWORD)))
                                 KEY-VARS KEYWORDS)
             ,@FORMS))))))

);NEHW-LAVE


;;; Restarts

(DEFVAR *RESTART-CLUSTERS* '())

(DEFUN COMPUTE-RESTARTS ()
  (COPY-LIST (APPLY #'APPEND *RESTART-CLUSTERS*)))

(DEFUN RESTART-PRINT (RESTART STREAM DEPTH)
  (DECLARE (IGNORE DEPTH))
  (IF *PRINT-ESCAPE*
      (FORMAT STREAM "#<~S.~D>" (TYPE-OF RESTART) (UNIQUE-ID RESTART))
      (RESTART-REPORT RESTART STREAM)))

(DEFSTRUCT (RESTART (:PRINT-FUNCTION RESTART-PRINT))
  NAME
  FUNCTION
  REPORT-FUNCTION
  INTERACTIVE-FUNCTION)

(DEFUN RESTART-REPORT (RESTART STREAM)
  (FUNCALL (OR (RESTART-REPORT-FUNCTION RESTART)
               (LET ((NAME (RESTART-NAME RESTART)))
		 #'(LAMBDA (STREAM)
		     (IF NAME (FORMAT STREAM "~S" NAME)
			      (FORMAT STREAM "~S" RESTART)))))
           STREAM))

(DEFMACRO RESTART-BIND (BINDINGS &BODY FORMS)
  `(LET ((*RESTART-CLUSTERS* (CONS (LIST ,@(MAPCAR #'(LAMBDA (BINDING)
						       `(MAKE-RESTART
							  :NAME     ',(CAR BINDING)
							  :FUNCTION ,(CADR BINDING)
							  ,@(CDDR BINDING)))
						   BINDINGS))
				   *RESTART-CLUSTERS*)))
     ,@FORMS))

(DEFUN FIND-RESTART (NAME)
  (DOLIST (RESTART-CLUSTER *RESTART-CLUSTERS*)
    (DOLIST (RESTART RESTART-CLUSTER)
      (WHEN (OR (EQ RESTART NAME) (EQ (RESTART-NAME RESTART) NAME))
	(RETURN-FROM FIND-RESTART RESTART)))))
  
(DEFUN INVOKE-RESTART (RESTART &REST VALUES)
  (LET ((REAL-RESTART (OR (FIND-RESTART RESTART)
			  (ERROR "Restart ~S is not active." RESTART))))
    (APPLY (RESTART-FUNCTION REAL-RESTART) VALUES)))

(DEFUN INVOKE-RESTART-INTERACTIVELY (RESTART)
  (LET ((REAL-RESTART (OR (FIND-RESTART RESTART)
			  (ERROR "Restart ~S is not active." RESTART))))
    (APPLY (RESTART-FUNCTION REAL-RESTART)
	   (LET ((INTERACTIVE-FUNCTION
		   (RESTART-INTERACTIVE-FUNCTION REAL-RESTART)))
	     (IF INTERACTIVE-FUNCTION
		 (FUNCALL INTERACTIVE-FUNCTION)
		 '())))))


(DEFMACRO RESTART-CASE (EXPRESSION &BODY CLAUSES)
  (FLET ((TRANSFORM-KEYWORDS (&KEY REPORT INTERACTIVE)
	   (LET ((RESULT '()))
	     (WHEN REPORT
	       (SETQ RESULT (LIST* (IF (STRINGP REPORT)
				       `#'(LAMBDA (STREAM)
					    (WRITE-STRING ,REPORT STREAM))
				       `#',REPORT)
				   :REPORT-FUNCTION
				   RESULT)))
	     (WHEN INTERACTIVE
	       (SETQ RESULT (LIST* `#',INTERACTIVE
				   :INTERACTIVE-FUNCTION
				   RESULT)))
	     (NREVERSE RESULT))))
    (LET ((BLOCK-TAG (GENSYM))
	  (TEMP-VAR  (GENSYM))
	  (DATA
	    (MAPCAR #'(LAMBDA (CLAUSE)
			(WITH-KEYWORD-PAIRS ((REPORT INTERACTIVE &REST FORMS)
					     (CDDR CLAUSE))
			  (LIST (CAR CLAUSE)			   ;Name=0
				(GENSYM)			   ;Tag=1
				(TRANSFORM-KEYWORDS :REPORT REPORT ;Keywords=2
						    :INTERACTIVE INTERACTIVE)
				(CADR CLAUSE)			   ;BVL=3
				FORMS)))			   ;Body=4
		    CLAUSES)))
      `(BLOCK ,BLOCK-TAG
	 (LET ((,TEMP-VAR NIL))
	   (TAGBODY
	     (RESTART-BIND
	       ,(MAPCAR #'(LAMBDA (DATUM)
			    (LET ((NAME (NTH 0 DATUM))
				  (TAG  (NTH 1 DATUM))
				  (KEYS (NTH 2 DATUM)))
			      `(,NAME #'(LAMBDA (&REST TEMP)
					  #+LISPM (SETQ TEMP (COPY-LIST TEMP))
					  (SETQ ,TEMP-VAR TEMP)
					  (GO ,TAG))
				,@KEYS)))
			DATA)
	       (RETURN-FROM ,BLOCK-TAG ,EXPRESSION))
	     ,@(MAPCAN #'(LAMBDA (DATUM)
			   (LET ((TAG  (NTH 1 DATUM))
				 (BVL  (NTH 3 DATUM))
				 (BODY (NTH 4 DATUM)))
			     (LIST TAG
				   `(RETURN-FROM ,BLOCK-TAG
				      (APPLY #'(LAMBDA ,BVL ,@BODY)
					     ,TEMP-VAR)))))
		       DATA)))))))

(DEFMACRO WITH-SIMPLE-RESTART ((RESTART-NAME FORMAT-STRING
					     &REST FORMAT-ARGUMENTS)
			       &BODY FORMS)
  `(RESTART-CASE (PROGN ,@FORMS)
     (,RESTART-NAME ()
        :REPORT (LAMBDA (STREAM)
		  (FORMAT STREAM ,FORMAT-STRING ,@FORMAT-ARGUMENTS))
      (VALUES NIL T))))


(DEFUN CONDITION-PRINT (CONDITION STREAM DEPTH)
  DEPTH ;ignored
  (COND (*PRINT-ESCAPE*
         (FORMAT STREAM "#<~S.~D>" (TYPE-OF CONDITION) (UNIQUE-ID CONDITION)))
        (T
         (CONDITION-REPORT CONDITION STREAM))))

(DEFSTRUCT (CONDITION :CONC-NAME
                      (:CONSTRUCTOR |Constructor for CONDITION|)
                      (:PREDICATE NIL)
                      (:PRINT-FUNCTION CONDITION-PRINT))
  (-DUMMY-SLOT- NIL))

(EVAL-WHEN (EVAL COMPILE LOAD)

(DEFMACRO PARENT-TYPE     (CONDITION-TYPE) `(GET ,CONDITION-TYPE 'PARENT-TYPE))
(DEFMACRO SLOTS           (CONDITION-TYPE) `(GET ,CONDITION-TYPE 'SLOTS))
(DEFMACRO CONC-NAME       (CONDITION-TYPE) `(GET ,CONDITION-TYPE 'CONC-NAME))
(DEFMACRO REPORT-FUNCTION (CONDITION-TYPE) `(GET ,CONDITION-TYPE 'REPORT-FUNCTION))
(DEFMACRO MAKE-FUNCTION   (CONDITION-TYPE) `(GET ,CONDITION-TYPE 'MAKE-FUNCTION))

);NEHW-LAVE

(DEFUN CONDITION-REPORT (CONDITION STREAM)
  (DO ((TYPE (TYPE-OF CONDITION) (PARENT-TYPE TYPE)))
      ((NOT TYPE) (FORMAT STREAM "The condition ~A occurred."))
    (LET ((REPORTER (REPORT-FUNCTION TYPE)))
      (WHEN REPORTER
        (FUNCALL REPORTER CONDITION STREAM)
        (RETURN NIL)))))

(SETF (MAKE-FUNCTION   'CONDITION) '|Constructor for CONDITION|)

(DEFUN MAKE-CONDITION (TYPE &REST SLOT-INITIALIZATIONS)
  (LET ((FN (MAKE-FUNCTION TYPE)))
    (COND ((NOT FN) (ERROR 'SIMPLE-TYPE-ERROR
			   :DATUM TYPE
			   :EXPECTED-TYPE '(SATISFIES MAKE-FUNCTION)
			   :FORMAT-STRING "Not a condition type: ~S"
			   :FORMAT-ARGUMENTS (LIST TYPE)))
          (T (APPLY FN SLOT-INITIALIZATIONS)))))

(EVAL-WHEN (EVAL COMPILE LOAD) ;Some utilities that are used at macro expansion time

(DEFMACRO RESOLVE-FUNCTION (FUNCTION EXPRESSION RESOLVER)
  `(COND ((AND ,FUNCTION ,EXPRESSION)
          (CERROR "Use only the :~A information."
                  "Only one of :~A and :~A is allowed."
                  ',FUNCTION ',EXPRESSION))
         (,EXPRESSION
          (SETQ ,FUNCTION ,RESOLVER))))
         
(DEFUN PARSE-NEW-AND-USED-SLOTS (SLOTS PARENT-TYPE)
  (LET ((NEW '()) (USED '()))
    (DOLIST (SLOT SLOTS)
      (IF (SLOT-USED-P (CAR SLOT) PARENT-TYPE)
          (PUSH SLOT USED)
          (PUSH SLOT NEW)))
    (VALUES NEW USED)))

(DEFUN SLOT-USED-P (SLOT-NAME TYPE)
  (COND ((EQ TYPE 'CONDITION) NIL)
        ((NOT TYPE) (ERROR "The type ~S does not inherit from CONDITION." TYPE))
        ((ASSOC SLOT-NAME (SLOTS TYPE)))
        (T
         (SLOT-USED-P SLOT-NAME (PARENT-TYPE TYPE)))))

);NEHW-LAVE

(DEFMACRO DEFINE-CONDITION (NAME (PARENT-TYPE) SLOT-SPECS &REST OPTIONS)
  (LET ((CONSTRUCTOR (LET ((*PACKAGE* *THIS-PACKAGE*)) ;Bind for the INTERN -and- the FORMAT
                       (INTERN (FORMAT NIL "Constructor for ~S" NAME)))))
    (LET ((SLOTS (MAPCAR #'(LAMBDA (SLOT-SPEC)
			     (IF (ATOM SLOT-SPEC) (LIST SLOT-SPEC) SLOT-SPEC))
			 SLOT-SPECS)))
      (MULTIPLE-VALUE-BIND (NEW-SLOTS USED-SLOTS)
          (PARSE-NEW-AND-USED-SLOTS SLOTS PARENT-TYPE)
	(LET ((CONC-NAME-P     NIL)
	      (CONC-NAME       NIL)
	      (REPORT-FUNCTION NIL)
	      (DOCUMENTATION   NIL))
	  (DO ((O OPTIONS (CDR O)))
	      ((NULL O))
	    (LET ((OPTION (CAR O)))
	      (CASE (CAR OPTION) ;Should be ECASE
		(:CONC-NAME (SETQ CONC-NAME-P T)
		 	    (SETQ CONC-NAME (CADR OPTION)))
		(:REPORT (SETQ REPORT-FUNCTION (IF (STRINGP (CADR OPTION))
						   `(LAMBDA (STREAM)
						      (WRITE-STRING ,(CADR OPTION) STREAM))
						   (CADR OPTION))))
		(:DOCUMENTATION (SETQ DOCUMENTATION (CADR OPTION)))
		(OTHERWISE (CERROR "Ignore this DEFINE-CONDITION option."
				   "Invalid DEFINE-CONDITION option: ~S" OPTION)))))
	  (IF (NOT CONC-NAME-P) (SETQ CONC-NAME (INTERN (FORMAT NIL "~A-" NAME) *PACKAGE*)))
          ;; The following three forms are compile-time side-effects. For now, they affect
          ;; the global environment, but with modified abstractions for PARENT-TYPE, SLOTS, 
          ;; and CONC-NAME, the compiler could easily make them local.
          (SETF (PARENT-TYPE NAME) PARENT-TYPE)
          (SETF (SLOTS NAME)       SLOTS)
          (SETF (CONC-NAME NAME)   CONC-NAME)
          ;; Finally, the expansion ...
          `(PROGN (DEFSTRUCT (,NAME
                              (:CONSTRUCTOR ,CONSTRUCTOR)
                              (:PREDICATE NIL)
			      (:COPIER NIL)
                              (:PRINT-FUNCTION CONDITION-PRINT)
                              (:INCLUDE ,PARENT-TYPE ,@USED-SLOTS)
                              (:CONC-NAME ,CONC-NAME))
                    ,@NEW-SLOTS)
		  (SETF (DOCUMENTATION ',NAME 'TYPE) ',DOCUMENTATION)
                  (SETF (PARENT-TYPE ',NAME) ',PARENT-TYPE)
                  (SETF (SLOTS ',NAME) ',SLOTS)
                  (SETF (CONC-NAME ',NAME) ',CONC-NAME)
                  (SETF (REPORT-FUNCTION ',NAME) ,(IF REPORT-FUNCTION `#',REPORT-FUNCTION))
                  (SETF (MAKE-FUNCTION ',NAME) ',CONSTRUCTOR)
                  ',NAME))))))


(EVAL-WHEN (EVAL COMPILE LOAD)

(DEFUN ACCUMULATE-CASES (MACRO-NAME CASES LIST-IS-ATOM-P)
  (DO ((L '())
       (C CASES (CDR C)))
      ((NULL C) (NREVERSE L))
    (LET ((KEYS (CAAR C)))
      (COND ((ATOM KEYS)
	     (COND ((NULL KEYS))
		   ((MEMBER KEYS '(OTHERWISE T))
		    (ERROR "OTHERWISE is not allowed in ~S expressions."
			   MACRO-NAME))
		   (T (PUSH KEYS L))))
	    (LIST-IS-ATOM-P
	     (PUSH KEYS L))
	    (T
	     (DOLIST (KEY KEYS) (PUSH KEY L)))))))

);NEHW-LAVE

(DEFMACRO ECASE (KEYFORM &REST CASES)
  (LET ((KEYS (ACCUMULATE-CASES 'ECASE CASES NIL))
	(VAR (GENSYM)))
    `(LET ((,VAR ,KEYFORM))
       (CASE ,VAR
	 ,@CASES
	 (OTHERWISE
	   (ERROR 'CASE-FAILURE :NAME 'ECASE
		  		:DATUM ,VAR
				:EXPECTED-TYPE '(MEMBER ,@KEYS)
				:POSSIBILITIES ',KEYS))))))

(DEFMACRO CCASE (KEYPLACE &REST CASES)
  (LET ((KEYS (ACCUMULATE-CASES 'CCASE CASES NIL))
	(TAG1 (GENSYM))
	(TAG2 (GENSYM)))
    `(BLOCK ,TAG1
       (TAGBODY ,TAG2
	 (RETURN-FROM ,TAG1
	   (CASE ,KEYPLACE
	     ,@CASES
	     (OTHERWISE
	       (RESTART-CASE (ERROR 'CASE-FAILURE
				    :NAME 'CCASE
				    :DATUM ,KEYPLACE
				    :EXPECTED-TYPE '(MEMBER ,@KEYS)
				    :POSSIBILITIES ',KEYS)
		 (STORE-VALUE (VALUE)
		     :REPORT (LAMBDA (STREAM)
			       (FORMAT STREAM "Supply a new value of ~S."
				       ',KEYPLACE))
		     :INTERACTIVE READ-EVALUATED-FORM
		   (SETF ,KEYPLACE VALUE)
		   (GO ,TAG2))))))))))



(DEFMACRO ETYPECASE (KEYFORM &REST CASES)
  (LET ((TYPES (ACCUMULATE-CASES 'ETYPECASE CASES T))
	(VAR (GENSYM)))
    `(LET ((,VAR ,KEYFORM))
       (TYPECASE ,VAR
	 ,@CASES
	 (OTHERWISE
	   (ERROR 'CASE-FAILURE :NAME 'ETYPECASE
		  		:DATUM ,VAR
				:EXPECTED-TYPE '(OR ,@TYPES)
				:POSSIBILITIES ',TYPES))))))

(DEFMACRO CTYPECASE (KEYPLACE &REST CASES)
  (LET ((TYPES (ACCUMULATE-CASES 'CTYPECASE CASES T))
	(TAG1 (GENSYM))
	(TAG2 (GENSYM)))
    `(BLOCK ,TAG1
       (TAGBODY ,TAG2
	 (RETURN-FROM ,TAG1
	   (TYPECASE ,KEYPLACE
	     ,@CASES
	     (OTHERWISE
	       (RESTART-CASE (ERROR 'CASE-FAILURE
				    :NAME 'CTYPECASE
				    :DATUM ,KEYPLACE
				    :EXPECTED-TYPE '(OR ,@TYPES)
				    :POSSIBILITIES ',TYPES)
		 (STORE-VALUE (VALUE)
		     :REPORT (LAMBDA (STREAM)
			       (FORMAT STREAM "Supply a new value of ~S."
				       ',KEYPLACE))
		     :INTERACTIVE READ-EVALUATED-FORM
		   (SETF ,KEYPLACE VALUE)
		   (GO ,TAG2))))))))))



(DEFUN ASSERT-REPORT (NAMES STREAM)
  (FORMAT STREAM "Retry assertion")
  (IF NAMES
      (FORMAT STREAM " with new value~P for ~{~S~^, ~}."
	      (LENGTH NAMES) NAMES)
      (FORMAT STREAM ".")))

(DEFUN ASSERT-PROMPT (NAME VALUE)
  (COND ((Y-OR-N-P "The old value of ~S is ~S.~
		  ~%Do you want to supply a new value? "
		   NAME VALUE)
	 (FORMAT *QUERY-IO* "~&Type a form to be evaluated:~%")
	 (FLET ((READ-IT () (EVAL (READ *QUERY-IO*))))
	   (IF (SYMBOLP NAME) ;Help user debug lexical variables
	       (PROGV (LIST NAME) (LIST VALUE) (READ-IT))
	       (READ-IT))))
	(T VALUE)))

(DEFUN SIMPLE-ASSERTION-FAILURE (ASSERTION)
  (ERROR 'SIMPLE-TYPE-ERROR
	 :DATUM ASSERTION
	 :EXPECTED-TYPE NIL			; This needs some work in next revision. -kmp
	 :FORMAT-STRING "The assertion ~S failed."
	 :FORMAT-ARGUMENTS (LIST ASSERTION)))

(DEFMACRO ASSERT (TEST-FORM &OPTIONAL PLACES DATUM &REST ARGUMENTS)
  (LET ((TAG (GENSYM)))
    `(TAGBODY ,TAG
       (UNLESS ,TEST-FORM
	 (RESTART-CASE ,(IF DATUM
			    `(ERROR ,DATUM ,@ARGUMENTS)
			    `(SIMPLE-ASSERTION-FAILURE ',TEST-FORM))
	   (CONTINUE ()
	       :REPORT (LAMBDA (STREAM) (ASSERT-REPORT ',PLACES STREAM))
	     ,@(MAPCAR #'(LAMBDA (PLACE)
			   `(SETF ,PLACE (ASSERT-PROMPT ',PLACE ,PLACE)))
		       PLACES)
             (GO ,TAG)))))))



(DEFUN READ-EVALUATED-FORM ()
  (FORMAT *QUERY-IO* "~&Type a form to be evaluated:~%")
  (LIST (EVAL (READ *QUERY-IO*))))

(DEFMACRO CHECK-TYPE (PLACE TYPE &OPTIONAL TYPE-STRING)
  (LET ((TAG1 (GENSYM))
	(TAG2 (GENSYM)))
    `(BLOCK ,TAG1
       (TAGBODY ,TAG2
	 (IF (TYPEP ,PLACE ',TYPE) (RETURN-FROM ,TAG1 NIL))
	 (RESTART-CASE ,(IF TYPE-STRING
			    `(ERROR "The value of ~S is ~S, ~
				     which is not ~A."
				    ',PLACE ,PLACE ,TYPE-STRING)
			    `(ERROR "The value of ~S is ~S, ~
				     which is not of type ~S."
				    ',PLACE ,PLACE ',TYPE))
	   (STORE-VALUE (VALUE)
	       :REPORT (LAMBDA (STREAM)
			 (FORMAT STREAM "Supply a new value of ~S."
				 ',PLACE))
	       :INTERACTIVE READ-EVALUATED-FORM
	     (SETF ,PLACE VALUE)
	     (GO ,TAG2)))))))

(DEFVAR *HANDLER-CLUSTERS* NIL)

(DEFMACRO HANDLER-BIND (BINDINGS &BODY FORMS)
  (UNLESS (EVERY #'(LAMBDA (X) (AND (LISTP X) (= (LENGTH X) 2))) BINDINGS)
    (ERROR "Ill-formed handler bindings."))
  `(LET ((*HANDLER-CLUSTERS* (CONS (LIST ,@(MAPCAR #'(LAMBDA (X) `(CONS ',(CAR X) ,(CADR X)))
						   BINDINGS))
				   *HANDLER-CLUSTERS*)))
     ,@FORMS))

(DEFVAR *BREAK-ON-SIGNALS* NIL)

(DEFUN SIGNAL (DATUM &REST ARGUMENTS)
  (LET ((CONDITION (COERCE-TO-CONDITION DATUM ARGUMENTS 'SIMPLE-CONDITION 'SIGNAL))
        (*HANDLER-CLUSTERS* *HANDLER-CLUSTERS*))
    (IF (TYPEP CONDITION *BREAK-ON-SIGNALS*)
	(BREAK "~A~%Break entered because of *BREAK-ON-SIGNALS*."
	       CONDITION))
    (LOOP (IF (NOT *HANDLER-CLUSTERS*) (RETURN))
          (LET ((CLUSTER (POP *HANDLER-CLUSTERS*)))
	    (DOLIST (HANDLER CLUSTER)
	      (WHEN (TYPEP CONDITION (CAR HANDLER))
		(FUNCALL (CDR HANDLER) CONDITION)
		(RETURN NIL) ;?
		))))
    NIL))



;;; COERCE-TO-CONDITION
;;;  Internal routine used in ERROR, CERROR, BREAK, and WARN for parsing the
;;;  hairy argument conventions into a single argument that's directly usable 
;;;  by all the other routines.

(DEFUN COERCE-TO-CONDITION (DATUM ARGUMENTS DEFAULT-TYPE FUNCTION-NAME)
  #+LISPM (SETQ ARGUMENTS (COPY-LIST ARGUMENTS))
  (COND ((TYPEP DATUM 'CONDITION)
	 (IF ARGUMENTS
	     (CERROR "Ignore the additional arguments."
		     'SIMPLE-TYPE-ERROR
		     :DATUM ARGUMENTS
		     :EXPECTED-TYPE 'NULL
		     :FORMAT-STRING "You may not supply additional arguments ~
				     when giving ~S to ~S."
		     :FORMAT-ARGUMENTS (LIST DATUM FUNCTION-NAME)))
	 DATUM)
        ((SYMBOLP DATUM)                  ;roughly, (SUBTYPEP DATUM 'CONDITION)
         (APPLY #'MAKE-CONDITION DATUM ARGUMENTS))
        ((STRINGP DATUM)
	 (MAKE-CONDITION DEFAULT-TYPE
                         :FORMAT-STRING DATUM
                         :FORMAT-ARGUMENTS ARGUMENTS))
        (T
         (ERROR 'SIMPLE-TYPE-ERROR
		:DATUM DATUM
		:EXPECTED-TYPE '(OR SYMBOL STRING)
		:FORMAT-STRING "Bad argument to ~S: ~S"
		:FORMAT-ARGUMENTS (LIST FUNCTION-NAME DATUM)))))

(DEFUN ERROR (DATUM &REST ARGUMENTS)
  (LET ((CONDITION (COERCE-TO-CONDITION DATUM ARGUMENTS 'SIMPLE-ERROR 'ERROR)))
    (SIGNAL CONDITION)
    (INVOKE-DEBUGGER CONDITION)))

(DEFUN CERROR (CONTINUE-STRING DATUM &REST ARGUMENTS)
  (WITH-SIMPLE-RESTART (CONTINUE "~A" (APPLY #'FORMAT NIL CONTINUE-STRING ARGUMENTS))
    (APPLY #'ERROR DATUM ARGUMENTS))
  NIL)

(DEFUN BREAK (&OPTIONAL (FORMAT-STRING "Break") &REST FORMAT-ARGUMENTS)
  (WITH-SIMPLE-RESTART (CONTINUE "Return from BREAK.")
    (INVOKE-DEBUGGER
      (MAKE-CONDITION 'SIMPLE-CONDITION
		      :FORMAT-STRING    FORMAT-STRING
		      :FORMAT-ARGUMENTS FORMAT-ARGUMENTS)))
  NIL)

(DEFINE-CONDITION WARNING (CONDITION) ())

(DEFUN WARN (DATUM &REST ARGUMENTS)
  (LET ((CONDITION
	  (COERCE-TO-CONDITION DATUM ARGUMENTS 'SIMPLE-WARNING 'WARN)))
    (CHECK-TYPE CONDITION WARNING "a warning condition")
    (IF *BREAK-ON-WARNINGS*
	(BREAK "~A~%Break entered because of *BREAK-ON-WARNINGS*."
	       CONDITION))
    (RESTART-CASE (SIGNAL CONDITION)
      (MUFFLE-WARNING ()
	  :REPORT "Skip warning."
	(RETURN-FROM WARN NIL)))
    (FORMAT *ERROR-OUTPUT* "~&Warning:~%~A~%" CONDITION)
    NIL))



(DEFINE-CONDITION SERIOUS-CONDITION (CONDITION) ())

(DEFINE-CONDITION ERROR (SERIOUS-CONDITION) ())

(DEFUN SIMPLE-CONDITION-PRINTER (CONDITION STREAM)
  (APPLY #'FORMAT STREAM (SIMPLE-CONDITION-FORMAT-STRING    CONDITION)
	 		 (SIMPLE-CONDITION-FORMAT-ARGUMENTS CONDITION)))

(DEFINE-CONDITION SIMPLE-CONDITION (CONDITION) (FORMAT-STRING (FORMAT-ARGUMENTS '()))
  (:CONC-NAME INTERNAL-SIMPLE-CONDITION-)
  (:REPORT SIMPLE-CONDITION-PRINTER))

(DEFINE-CONDITION SIMPLE-WARNING (WARNING) (FORMAT-STRING (FORMAT-ARGUMENTS '()))
  (:CONC-NAME INTERNAL-SIMPLE-WARNING-)
  (:REPORT SIMPLE-CONDITION-PRINTER))

(DEFINE-CONDITION SIMPLE-ERROR (ERROR) (FORMAT-STRING (FORMAT-ARGUMENTS '()))
  (:CONC-NAME INTERNAL-SIMPLE-ERROR-)
  (:REPORT SIMPLE-CONDITION-PRINTER))

(DEFINE-CONDITION STORAGE-CONDITION (SERIOUS-CONDITION) ())

(DEFINE-CONDITION STACK-OVERFLOW    (STORAGE-CONDITION) ())
(DEFINE-CONDITION STORAGE-EXHAUSTED (STORAGE-CONDITION) ())

(DEFINE-CONDITION TYPE-ERROR (ERROR) (DATUM EXPECTED-TYPE))

(DEFINE-CONDITION SIMPLE-TYPE-ERROR (TYPE-ERROR) (FORMAT-STRING (FORMAT-ARGUMENTS '()))
  (:CONC-NAME INTERNAL-SIMPLE-TYPE-ERROR-)
  (:REPORT SIMPLE-CONDITION-PRINTER))

(DEFINE-CONDITION CASE-FAILURE (TYPE-ERROR) (NAME POSSIBILITIES)
  (:REPORT
    (LAMBDA (CONDITION STREAM)
      (FORMAT STREAM "~S fell through ~S expression.~%Wanted one of ~:S."
	      (TYPE-ERROR-DATUM CONDITION)
	      (CASE-FAILURE-NAME CONDITION)
	      (CASE-FAILURE-POSSIBILITIES CONDITION)))))

(DEFUN SIMPLE-CONDITION-FORMAT-STRING (CONDITION)
  (ETYPECASE CONDITION
    (SIMPLE-CONDITION  (INTERNAL-SIMPLE-CONDITION-FORMAT-STRING  CONDITION))
    (SIMPLE-WARNING    (INTERNAL-SIMPLE-WARNING-FORMAT-STRING    CONDITION))
    (SIMPLE-TYPE-ERROR (INTERNAL-SIMPLE-TYPE-ERROR-FORMAT-STRING CONDITION))
    (SIMPLE-ERROR      (INTERNAL-SIMPLE-ERROR-FORMAT-STRING      CONDITION))))

(DEFUN SIMPLE-CONDITION-FORMAT-ARGUMENTS (CONDITION)
  (ETYPECASE CONDITION
    (SIMPLE-CONDITION  (INTERNAL-SIMPLE-CONDITION-FORMAT-ARGUMENTS  CONDITION))
    (SIMPLE-WARNING    (INTERNAL-SIMPLE-WARNING-FORMAT-ARGUMENTS    CONDITION))
    (SIMPLE-TYPE-ERROR (INTERNAL-SIMPLE-TYPE-ERROR-FORMAT-ARGUMENTS CONDITION))
    (SIMPLE-ERROR      (INTERNAL-SIMPLE-ERROR-FORMAT-ARGUMENTS      CONDITION))))

(DEFINE-CONDITION PROGRAM-ERROR (ERROR) ())

(DEFINE-CONDITION CONTROL-ERROR (ERROR) ())

(DEFINE-CONDITION STREAM-ERROR (ERROR) (STREAM))

(DEFINE-CONDITION END-OF-FILE (STREAM-ERROR) ())

(DEFINE-CONDITION FILE-ERROR (ERROR) (PATHNAME))

(DEFINE-CONDITION PACKAGE-ERROR (ERROR) (PATHNAME))



(DEFINE-CONDITION CELL-ERROR (ERROR) (NAME))

(DEFINE-CONDITION UNBOUND-VARIABLE (CELL-ERROR) ()
  (:REPORT (LAMBDA (CONDITION STREAM)
	     (FORMAT STREAM "The variable ~S is unbound."
		     (CELL-ERROR-NAME CONDITION)))))
  
(DEFINE-CONDITION UNDEFINED-FUNCTION (CELL-ERROR) ()
  (:REPORT (LAMBDA (CONDITION STREAM)
	     (FORMAT STREAM "The function ~S is undefined."
		     (CELL-ERROR-NAME CONDITION)))))

(DEFINE-CONDITION ARITHMETIC-ERROR (ERROR) (OPERATION OPERANDS))

(DEFINE-CONDITION DIVISION-BY-ZERO         (ARITHMETIC-ERROR) ())
(DEFINE-CONDITION FLOATING-POINT-OVERFLOW  (ARITHMETIC-ERROR) ())
(DEFINE-CONDITION FLOATING-POINT-UNDERFLOW (ARITHMETIC-ERROR) ())



(DEFMACRO HANDLER-CASE (FORM &REST CASES)
  (LET ((NO-ERROR-CLAUSE (ASSOC ':NO-ERROR CASES)))
    (IF NO-ERROR-CLAUSE
	(LET ((NORMAL-RETURN (MAKE-SYMBOL "NORMAL-RETURN"))
	      (ERROR-RETURN  (MAKE-SYMBOL "ERROR-RETURN")))
	  `(BLOCK ,ERROR-RETURN
	     (MULTIPLE-VALUE-CALL #'(LAMBDA ,@(CDR NO-ERROR-CLAUSE))
	       (BLOCK ,NORMAL-RETURN
		 (RETURN-FROM ,ERROR-RETURN
		   (HANDLER-CASE (RETURN-FROM ,NORMAL-RETURN ,FORM)
		     ,@(REMOVE NO-ERROR-CLAUSE CASES)))))))
	(LET ((TAG (GENSYM))
	      (VAR (GENSYM))
	      (ANNOTATED-CASES (MAPCAR #'(LAMBDA (CASE) (CONS (GENSYM) CASE))
				       CASES)))
	  `(BLOCK ,TAG
	     (LET ((,VAR NIL))
	       ,VAR				;ignorable
	       (TAGBODY
		 (HANDLER-BIND ,(MAPCAR #'(LAMBDA (ANNOTATED-CASE)
					    (LIST (CADR ANNOTATED-CASE)
						  `#'(LAMBDA (TEMP)
						       ,@(IF (CADDR ANNOTATED-CASE)
							     `((SETQ ,VAR TEMP)))
						       (GO ,(CAR ANNOTATED-CASE)))))
					ANNOTATED-CASES)
			       (RETURN-FROM ,TAG ,FORM))
		 ,@(MAPCAN #'(LAMBDA (ANNOTATED-CASE)
			       (LIST (CAR ANNOTATED-CASE)
				     (LET ((BODY (CDDDR ANNOTATED-CASE)))
				       `(RETURN-FROM ,TAG
					  ,(COND ((CADDR ANNOTATED-CASE)
						  `(LET ((,(CAADDR ANNOTATED-CASE)
							  ,VAR))
						     ,@BODY))
						 ((NOT (CDR BODY))
						  (CAR BODY))
						 (T
						  `(PROGN ,@BODY)))))))
			   ANNOTATED-CASES))))))))

(DEFMACRO IGNORE-ERRORS (&REST FORMS)
  `(HANDLER-CASE (PROGN ,@FORMS)
     (ERROR (CONDITION) (VALUES NIL CONDITION))))

(DEFINE-CONDITION ABORT-FAILURE (CONTROL-ERROR) ()
  (:REPORT "Abort failed."))

(DEFUN ABORT          ()      (INVOKE-RESTART 'ABORT)
       			      (ERROR 'ABORT-FAILURE))
(DEFUN CONTINUE       ()      (INVOKE-RESTART 'CONTINUE))
(DEFUN MUFFLE-WARNING ()      (INVOKE-RESTART 'MUFFLE-WARNING))
(DEFUN STORE-VALUE    (VALUE) (INVOKE-RESTART 'STORE-VALUE VALUE))
(DEFUN USE-VALUE      (VALUE) (INVOKE-RESTART 'USE-VALUE   VALUE))



(DEFVAR *DEBUG-LEVEL* 0)
(DEFVAR *DEBUG-ABORT* NIL)
(DEFVAR *DEBUG-CONTINUE* NIL)
(DEFVAR *DEBUG-CONDITION* NIL)
(DEFVAR *DEBUG-RESTARTS* NIL)
(DEFVAR *NUMBER-OF-DEBUG-RESTARTS* 0)
(DEFVAR *DEBUG-EVAL* 'EVAL)
(DEFVAR *DEBUG-PRINT* #'(LAMBDA (VALUES) (FORMAT T "~&~{~S~^,~%~}" VALUES)))

(DEFMACRO DEBUG-COMMAND                (X) `(GET ,X 'DEBUG-COMMAND))
(DEFMACRO DEBUG-COMMAND-ARGUMENT-COUNT (X) `(GET ,X 'DEBUG-COMMAND-ARGUMENT-COUNT))

(DEFMACRO DEFINE-DEBUG-COMMAND (NAME BVL &REST BODY)
  `(PROGN (SETF (DEBUG-COMMAND ',NAME) #'(LAMBDA ,BVL ,@BODY))
          (SETF (DEBUG-COMMAND-ARGUMENT-COUNT ',NAME) ,(LENGTH BVL))
          ',NAME))

(DEFUN READ-DEBUG-COMMAND ()
  (FORMAT T "~&Debug ~D> " *DEBUG-LEVEL*)
  (COND ((CHAR= (PEEK-CHAR T) #\:)
	 (WITH-INPUT-FROM-STRING (STREAM (READ-LINE))
	   (LET ((EOF (LIST NIL)))
	     (DO ((FORM (LET ((*PACKAGE* (FIND-PACKAGE "KEYWORD")))
			  (READ-CHAR) ;Eat the ":" so that ":1" reliably reads a number.
			  (READ STREAM NIL EOF))
			(READ STREAM NIL EOF))
		  (L '() (CONS FORM L)))
		 ((EQ FORM EOF) (NREVERSE L))))))
	(T
	 (LIST :EVAL (READ)))))
                   
(DEFINE-DEBUG-COMMAND :EVAL (FORM)
  (FUNCALL *DEBUG-PRINT* (MULTIPLE-VALUE-LIST (FUNCALL *DEBUG-EVAL* FORM))))

(DEFINE-DEBUG-COMMAND :ABORT ()
  (IF *DEBUG-ABORT*
      (INVOKE-RESTART-INTERACTIVELY *DEBUG-ABORT*)
      (FORMAT T "~&There is no way to abort.~%")))

(DEFINE-DEBUG-COMMAND :CONTINUE ()
  (IF *DEBUG-CONTINUE*
      (INVOKE-RESTART-INTERACTIVELY *DEBUG-CONTINUE*)
      (FORMAT T "~&There is no way to continue.~%")))

(DEFINE-DEBUG-COMMAND :ERROR ()
  (FORMAT T "~&~A~%" *DEBUG-CONDITION*))

(DEFINE-DEBUG-COMMAND :HELP ()
  (FORMAT T "~&You are in a portable debugger.~
             ~%Type a debugger command or a form to evaluate.~
             ~%Commands are:~%")
  (SHOW-RESTARTS *DEBUG-RESTARTS* *NUMBER-OF-DEBUG-RESTARTS* 16)
  (FORMAT T "~& :EVAL form     Evaluate a form.~
             ~% :HELP          Show this text.~%")
  (IF *DEBUG-ABORT*    (FORMAT T "~& :ABORT         Exit by ABORT.~%"))
  (IF *DEBUG-CONTINUE* (FORMAT T "~& :CONTINUE      Exit by CONTINUE.~%"))
  (FORMAT T "~& :ERROR         Reprint error message.~%"))



(DEFUN SHOW-RESTARTS (&OPTIONAL (RESTARTS *DEBUG-RESTARTS*)
		      		(MAX *NUMBER-OF-DEBUG-RESTARTS*)
				TARGET-COLUMN)
  (UNLESS MAX (SETQ MAX (LENGTH RESTARTS)))
  (WHEN RESTARTS
    (DO ((W (IF TARGET-COLUMN
		(- TARGET-COLUMN 3)
		(CEILING (LOG MAX 10))))
         (P RESTARTS (CDR P))
         (I 0 (1+ I)))
        ((OR (NOT P) (= I MAX)))
      (FORMAT T "~& :~A "
	      (LET ((S (FORMAT NIL "~D" (+ I 1))))
		(WITH-OUTPUT-TO-STRING (STR)
		  (FORMAT STR "~A" S)
		  (DOTIMES (I (- W (LENGTH S)))
		    (WRITE-CHAR #\Space STR)))))
      (IF (EQ (CAR P) *DEBUG-ABORT*) (FORMAT T "(Abort) "))
      (IF (EQ (CAR P) *DEBUG-CONTINUE*) (FORMAT T "(Continue) "))
      (FORMAT T "~A" (CAR P))
      (FORMAT T "~%"))))

(DEFUN INVOKE-DEBUGGER (&OPTIONAL (DATUM "Debug") &REST ARGUMENTS)
  (LET ((CONDITION (COERCE-TO-CONDITION DATUM ARGUMENTS 'SIMPLE-CONDITION 'DEBUG)))
    (WHEN *DEBUGGER-HOOK*
      (LET ((HOOK *DEBUGGER-HOOK*)
	    (*DEBUGGER-HOOK* NIL))
	(FUNCALL HOOK CONDITION HOOK)))
    (STANDARD-DEBUGGER CONDITION)))

(DEFUN STANDARD-DEBUGGER (CONDITION)
  (LET* ((*DEBUG-LEVEL* (1+ *DEBUG-LEVEL*))
	 (*DEBUG-RESTARTS* (COMPUTE-RESTARTS))
	 (*NUMBER-OF-DEBUG-RESTARTS* (LENGTH *DEBUG-RESTARTS*))
	 (*DEBUG-ABORT*    (FIND-RESTART 'ABORT))
	 (*DEBUG-CONTINUE* (OR (LET ((C (FIND-RESTART 'CONTINUE)))
				 (IF (OR (NOT *DEBUG-CONTINUE*)
					 (NOT (EQ *DEBUG-CONTINUE* C)))
				     C NIL))
			       (LET ((C (IF *DEBUG-RESTARTS*
					    (FIRST *DEBUG-RESTARTS*) NIL)))
				 (IF (NOT (EQ C *DEBUG-ABORT*)) C NIL))))
	 (*DEBUG-CONDITION* CONDITION))
    (FORMAT T "~&~A~%" CONDITION)
    (SHOW-RESTARTS)
    (DO ((COMMAND (READ-DEBUG-COMMAND)
		  (READ-DEBUG-COMMAND)))
	(NIL)
      (EXECUTE-DEBUGGER-COMMAND (CAR COMMAND) (CDR COMMAND) *DEBUG-LEVEL*))))

(DEFUN EXECUTE-DEBUGGER-COMMAND (CMD ARGS LEVEL)
  (WITH-SIMPLE-RESTART (ABORT "Return to debug level ~D." LEVEL)
    (COND ((NOT CMD))
	  ((INTEGERP CMD)
	   (COND ((AND (PLUSP CMD)
		       (< CMD (+ *NUMBER-OF-DEBUG-RESTARTS* 1)))
		  (LET ((RESTART (NTH (- CMD 1) *DEBUG-RESTARTS*)))
		    (IF ARGS
			(APPLY #'INVOKE-RESTART RESTART (MAPCAR *DEBUG-EVAL* ARGS))
			(INVOKE-RESTART-INTERACTIVELY RESTART))))
		 (T
		  (FORMAT T "~&No such restart."))))
	  (T
	   (LET ((FN (DEBUG-COMMAND CMD)))
	     (IF FN
		 (COND ((NOT (= (LENGTH ARGS) (DEBUG-COMMAND-ARGUMENT-COUNT CMD)))
			(FORMAT T "~&Too ~:[few~;many~] arguments to ~A."
				(> (LENGTH ARGS) (DEBUG-COMMAND-ARGUMENT-COUNT CMD))
				CMD))
		       (T
			(APPLY FN ARGS)))
		 (FORMAT T "~&~S is not a debugger command.~%" CMD)))))))


;;;; Sample Use
;;;
;;; To install this condition system, you must make your evaluator call the
;;; functions above. To make it more useful, you should try to establish reasonable
;;; restarts. What follows is an illustration of how this might be done if your
;;; evaluator were actually written in Lisp. (Note: The evaluator shown is not
;;; following CL evaluation rules, but that's not relevant to the points we're trying
;;; to make here.)

#|| 

(DEFUN PROMPT-FOR (TYPE &OPTIONAL PROMPT)
  (FLET ((TRY () (FORMAT T "~&~A? " (OR PROMPT TYPE)) (READ)))
    (DO ((ANS (TRY) (TRY)))
        ((TYPEP ANS TYPE) ANS)
      (FORMAT T "~&Wrong type of response -- wanted ~S~%" TYPE))))

(DEFUN MY-PROMPT-FOR-VALUE ()
  (LIST (MY-EVAL (PROMPT-FOR T "Value"))))

(DEFUN MY-REPL ()
  (LET ((*DEBUG-EVAL* 'MY-EVAL)
	(*DEBUG-PRINT* 'MY-PRINT))
    (DO ((FORM (PROMPT-FOR 'T "Eval")
               (PROMPT-FOR 'T "Eval")))
        ((NOT FORM))
      (WITH-SIMPLE-RESTART (ABORT "Return to MY-REPL toplevel.")
	(MY-PRINT (MULTIPLE-VALUE-LIST (MY-EVAL FORM)))))))

(DEFUN MY-PRINT (VALUES)
  (FORMAT T "~{~&=> ~S~}" VALUES))

(DEFUN MY-APPLY (FN &REST ARGS)
  (IF (FUNCTIONP FN)
      (APPLY #'APPLY FN ARGS)
      (RESTART-CASE (ERROR "Invalid function: ~S" FN)
        (USE-VALUE (X)
            :REPORT "Use a different function."
	    :INTERACTIVE MY-PROMPT-FOR-VALUE
          (APPLY #'MY-APPLY X ARGS)))))

(DEFUN MY-EVAL (X)
  (COND ((NUMBERP X) X)
        ((SYMBOLP X) (MY-EVAL-SYMBOL X))
	((STRINGP X) X)
        ((ATOM X) (ERROR "Illegal form: ~S" X))
        ((NOT (ATOM (CAR X)))
         (MY-APPLY (MY-EVAL (CAR X)) (MAPCAR #'MY-EVAL (CDR X))))
        ((EQ (CAR X) 'LAMBDA)
         #'(LAMBDA (&REST ARGS)
	     (MY-EVAL `(LET ,(MAPCAR #'LIST (CADR X) ARGS) ,@(CDDR X)))))
        ((MEMBER (CAR X) '(QUOTE FUNCTION)) (CADR X))
        ((EQ (CAR X) 'SETQ) (SETF (SYMBOL-VALUE (CADR X)) (MY-EVAL (CADDR X))))
        ((EQ (CAR X) 'DEFUN) (SETF (SYMBOL-FUNCTION (CADR X))
                                   (MY-EVAL `(LAMBDA ,@(CDDR X)))))
        ((EQ (CAR X) 'IF) (IF (MY-EVAL (CADR X))
                              (MY-EVAL (CADDR X))
                              (MY-EVAL (CADDDR X))))
        ((EQ (CAR X) 'LET) (PROGV (MAPCAR #'CAR (CADR X))
                                  (MAPCAR #'MY-EVAL (MAPCAR #'CADR (CADR X)))
			     (MY-EVAL `(PROGN ,@(CDDR X)))))
	((EQ (CAR X) 'PROGN) (DO ((L (CDR X) (CDR L)))
                                 ((NOT (CDR L)) (MY-EVAL (CAR L)))
                               (MY-EVAL (CAR L))))
        ((NOT (SYMBOLP (CAR X))) (ERROR "Illegal form: ~S" X))
        (T (MY-APPLY (MY-FEVAL-SYMBOL (CAR X)) (MAPCAR #'MY-EVAL (CDR X))))))


(DEFUN MY-EVAL-SYMBOL (X)
  (IF (BOUNDP X)
      (SYMBOL-VALUE X)
      (RESTART-CASE (ERROR 'UNBOUND-VARIABLE :NAME X)
	(USE-VALUE (VALUE)
            :REPORT (LAMBDA (STREAM)
		      (FORMAT STREAM "Specify another value of ~S to use this time." X))
	    :INTERACTIVE MY-PROMPT-FOR-VALUE
	  VALUE)
	(NIL ()
	    :REPORT (LAMBDA (STREAM)
		      (FORMAT STREAM "Retry the SYMBOL-VALUE operation on ~S." X))
	  (MY-EVAL-SYMBOL X))
	(MY-STORE-VALUE (VALUE)
	    :REPORT (LAMBDA (STREAM)
		      (FORMAT STREAM "Specify another value of ~S to store and use." X))
	    :INTERACTIVE MY-PROMPT-FOR-VALUE
	  (SETF (SYMBOL-VALUE X) VALUE)
	  VALUE))))

(DEFUN MY-FEVAL-SYMBOL (X)
  (IF (FBOUNDP X)
      (SYMBOL-FUNCTION X)
      (RESTART-CASE (ERROR 'UNDEFINED-FUNCTION :NAME X)
	(USE-VALUE (VALUE)
	    :REPORT (LAMBDA (STREAM)
		      (FORMAT STREAM "Specify a function to use instead of ~S this time." X))
	    :INTERACTIVE MY-PROMPT-FOR-VALUE
	  VALUE)
	(NIL ()
	    :REPORT (LAMBDA (STREAM)
		      (FORMAT STREAM "Retry the SYMBOL-FUNCTION operation on ~S." X))
	  (MY-FEVAL-SYMBOL X))
	(MY-STORE-VALUE (VALUE)
	    :REPORT MY-PROMPT-FOR-VALUE
	  (SETF (SYMBOL-FUNCTION X) VALUE)
	  VALUE))))

||# ;; End of sample application
