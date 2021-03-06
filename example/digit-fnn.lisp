(cl:defpackage :mgl-example-digit-fnn
  (:use #:common-lisp #:mgl))

(in-package :mgl-example-digit-fnn)

;;; There are 10 possible digits used as inputs ...
(defparameter *n-inputs* 10)
;;; and we want to learn the rule that maps the input digit D to (MOD
;;; (1+ D) 3).
(defparameter *n-outputs* 3)

;;; We define a feed-forward net to be able to specialize how inputs
;;; are translated by adding a SET-INPUT method later.
(defclass digit-fnn (fnn)
  ())

;;; Build a DIGIT-FNN with a single hidden layer of rectified linear
;;; units and a softmax output.
(defun make-digit-fnn (&key (n-hiddens 5))
  (build-fnn (:class 'digit-fnn)
    (input (->input :size *n-inputs*))
    (hidden-activation (->activation input :size n-hiddens))
    (hidden (->relu hidden-activation))
    (output-activation (->activation hidden :size *n-outputs*))
    (output (->softmax-xe-loss output-activation))))

;;; This method is called with batches of 'instances' (input digits in
;;; this case) by MINIMIZE and also by MONITOR-BPN-RESULTS before
;;; performing a forward pass (i.e. computing the value of the
;;; function represented by the network). Its job is to encode the
;;; inputs by populating rows of the NODES matrix of the INPUT clump.
;;;
;;; Each input is encoded as a row of zeros with a single 1 at index
;;; determined by the input digit. This is called one-hot encoding.
;;; The TARGET could be encoded the same way, but instead we use the
;;; sparse option supported by TARGET of ->SOFTMAX-XE-LOSS.
(defmethod set-input (digits (fnn digit-fnn))
  (let* ((input (nodes (find-clump 'input fnn)))
         (output-lump (find-clump 'output fnn)))
    (fill! 0 input)
    (loop for i upfrom 0
          for digit in digits
          do (setf (mref input i digit) 1))
    (setf (target output-lump)
          (mapcar (lambda (digit)
                    (mod (1+ digit) *n-outputs*))
                  digits))))

;;; Train the network by minimizing the loss (cross-entropy here) with
;;; stochastic gradient descent.
(defun train-digit-fnn ()
  (let ((optimizer
          ;; First create the optimizer for MINIMIZE.
          (make-instance 'segmented-gd-optimizer
                         :segmenter
                         ;; We train each weight lump with the same
                         ;; parameters and, in fact, the same
                         ;; optimizer. But it need not be so, in
                         ;; general.
                         (constantly
                          (make-instance 'sgd-optimizer
                                         :learning-rate 1
                                         :momentum 0.9
                                         :batch-size 100))))
        (fnn (make-digit-fnn)))
    ;; The number of instances the FNN can work with in parallel. It's
    ;; usually equal to the batch size or is a its divisor.
    (setf (max-n-stripes fnn) 50)
    ;; Initialize all weights randomly.
    (map-segments (lambda (weights)
                    (gaussian-random! (nodes weights) :stddev 0.01))
                  fnn)
    ;; Arrange for training and test error to be logged.
    (monitor-optimization-periodically
     optimizer '((:fn log-test-error :period 10000)
                 (:fn reset-optimization-monitors :period 1000)))
    ;; Finally, start the optimization.
    (minimize optimizer
              ;; Dress FNN in a BP-LEARNER and attach monitors for the
              ;; cost to it. These monitors are going to be logged and
              ;; reset after every 100 training instance by
              ;; RESET-OPTIMIZATION-MONITORS above.
              (make-instance 'bp-learner
                             :bpn fnn
                             :monitors (make-cost-monitors
                                        fnn :attributes `(:event "train")))
              ;; Training stops when the sampler runs out (after 10000
              ;; instances).
              :dataset (make-sampler 10000))))

;;; Return a sampler object that produces MAX-N-SAMPLES number of
;;; random inputs (numbers between 0 and 9).
(defun make-sampler (max-n-samples)
  (make-instance 'function-sampler :max-n-samples max-n-samples
                 :generator (lambda () (random *n-inputs*))))

;;; Log the test error. Also, describe the optimizer and the bpn at
;;; the beginning of training. Called periodically during training
;;; (see above).
(defun log-test-error (optimizer learner)
  (when (zerop (n-instances optimizer))
    (describe optimizer)
    (describe (bpn learner)))
  (log-padded
   (monitor-bpn-results (make-sampler 1000) (bpn learner)
                        (make-cost-monitors
                         (bpn learner) :attributes `(:event "pred.")))))

#|

;;; Transcript follows:
(repeatably ()
  (let ((*log-time* nil))
    (train-digit-fnn)))
.. training at n-instances: 0
.. train cost: 0.000e+0 (0)
.. #<SEGMENTED-GD-OPTIMIZER {100E112E93}>
..  SEGMENTED-GD-OPTIMIZER description:
..    N-INSTANCES = 0
..    OPTIMIZERS = (#<SGD-OPTIMIZER
..                    #<SEGMENT-SET
..                      (#<->WEIGHT # :SIZE 15 1/1 :NORM 0.04473>
..                       #<->WEIGHT # :SIZE 3 1/1 :NORM 0.01850>
..                       #<->WEIGHT # :SIZE 50 1/1 :NORM 0.07159>
..                       #<->WEIGHT # :SIZE 5 1/1 :NORM 0.03056>)
..                      {100E335B73}>
..                    {100E06DF83}>)
..    SEGMENTS = (#<->WEIGHT (HIDDEN OUTPUT-ACTIVATION) :SIZE
..                  15 1/1 :NORM 0.04473>
..                #<->WEIGHT (:BIAS OUTPUT-ACTIVATION) :SIZE
..                  3 1/1 :NORM 0.01850>
..                #<->WEIGHT (INPUT HIDDEN-ACTIVATION) :SIZE
..                  50 1/1 :NORM 0.07159>
..                #<->WEIGHT (:BIAS HIDDEN-ACTIVATION) :SIZE
..                  5 1/1 :NORM 0.03056>)
..  
.. #<SGD-OPTIMIZER {100E06DF83}>
..  GD-OPTIMIZER description:
..    N-INSTANCES = 0
..    SEGMENT-SET = #<SEGMENT-SET
..                    (#<->WEIGHT (HIDDEN OUTPUT-ACTIVATION) :SIZE
..                       15 1/1 :NORM 0.04473>
..                     #<->WEIGHT (:BIAS OUTPUT-ACTIVATION) :SIZE
..                       3 1/1 :NORM 0.01850>
..                     #<->WEIGHT (INPUT HIDDEN-ACTIVATION) :SIZE
..                       50 1/1 :NORM 0.07159>
..                     #<->WEIGHT (:BIAS HIDDEN-ACTIVATION) :SIZE
..                       5 1/1 :NORM 0.03056>)
..                    {100E335B73}>
..    LEARNING-RATE = 1.00000e+0
..    MOMENTUM = 9.00000e-1
..    MOMENTUM-TYPE = :NORMAL
..    WEIGHT-DECAY = 0.00000e+0
..    WEIGHT-PENALTY = 0.00000e+0
..    N-AFTER-UPATE-HOOK = 0
..    BATCH-SIZE = 100
..  
..  BATCH-GD-OPTIMIZER description:
..    N-BEFORE-UPATE-HOOK = 0
..  #<DIGIT-FNN {100E11A423}>
..   BPN description:
..     CLUMPS = #(#<->INPUT INPUT :SIZE 10 1/50 :NORM 0.00000>
..                #<->ACTIVATION
..                  (HIDDEN-ACTIVATION :ACTIVATION) :STRIPES 1/50
..                  :CLUMPS 4>
..                #<->RELU HIDDEN :SIZE 5 1/50 :NORM 0.00000>
..                #<->ACTIVATION
..                  (OUTPUT-ACTIVATION :ACTIVATION) :STRIPES 1/50
..                  :CLUMPS 4>
..                #<->SOFTMAX-XE-LOSS OUTPUT :SIZE 3 1/50 :NORM 0.00000>)
..     N-STRIPES = 1
..     MAX-N-STRIPES = 50
..   pred. cost: 1.100d+0 (1000.00)
.. training at n-instances: 1000
.. train cost: 1.093d+0 (1000.00)
.. training at n-instances: 2000
.. train cost: 5.886d-1 (1000.00)
.. training at n-instances: 3000
.. train cost: 3.574d-3 (1000.00)
.. training at n-instances: 4000
.. train cost: 1.601d-7 (1000.00)
.. training at n-instances: 5000
.. train cost: 1.973d-9 (1000.00)
.. training at n-instances: 6000
.. train cost: 4.882d-10 (1000.00)
.. training at n-instances: 7000
.. train cost: 2.771d-10 (1000.00)
.. training at n-instances: 8000
.. train cost: 2.283d-10 (1000.00)
.. training at n-instances: 9000
.. train cost: 2.123d-10 (1000.00)
.. training at n-instances: 10000
.. train cost: 2.263d-10 (1000.00)
.. pred. cost: 2.210d-10 (1000.00)
..
==> (#<->WEIGHT (:BIAS HIDDEN-ACTIVATION) :SIZE 5 1/1 :NORM 2.94294>
-->  #<->WEIGHT (INPUT HIDDEN-ACTIVATION) :SIZE 50 1/1 :NORM 11.48995>
-->  #<->WEIGHT (:BIAS OUTPUT-ACTIVATION) :SIZE 3 1/1 :NORM 3.39103>
-->  #<->WEIGHT (HIDDEN OUTPUT-ACTIVATION) :SIZE 15 1/1 :NORM 11.39339>)

|#
