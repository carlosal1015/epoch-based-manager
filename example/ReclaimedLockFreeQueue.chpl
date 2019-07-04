module ReclaimedLockFreeQueue {

  use EpochManager;
  use LocalAtomics;

  class node {
    type eltType;
    var val : eltType;
    var next : LocalAtomicObject(unmanaged node(eltType));

    proc init(val : ?eltType) {
      this.eltType = eltType;
      this.val = val;
    }

    proc init(type eltType) {
      this.eltType = eltType;
    }
  }

  class TokenWrapper {
    var _tok : unmanaged _token;
    
    proc init(_tok : unmanaged _token) {
      this._tok = _tok;
    }

    proc deinit() {
      _tok.unregister();
    }
    
    forwarding _tok;
  }

  class ReclaimedLockFreeQueue {
    type objType;
    var _head : LocalAtomicObject(unmanaged node(objType));
    var _tail : LocalAtomicObject(unmanaged node(objType));
    var _manager = new owned EpochManager();

    proc init(type objType) {
      this.objType = objType;
      this.complete();
      var _node = new unmanaged node(objType);
      _head.write(_node);
      _tail.write(_node);
    }

    proc getToken() {
      return new owned TokenWrapper(_manager.register());
    }

    proc enqueue(newObj : objType, tok) {
      var n = new unmanaged node(newObj);
      tok.pin();
      while (true) {
        var curr_tail = _tail.read();
        var next = curr_tail.next.read();
        if (next == nil) {
          if (curr_tail.next.compareExchange(next, n)) {
            _tail.compareExchange(curr_tail, n);
            break;
          }
        }
        else {
          _tail.compareExchange(curr_tail, next);
        }
      }
      tok.unpin();
    }

    proc dequeue(tok) : (bool, objType) {
      tok.pin();
      while (true) {
        var curr_head = _head.read();
        var curr_tail = _tail.read();
        var next_node = curr_head.next.read();

        if (curr_head == curr_tail) {
          if (next_node == nil) {
            tok.unpin();
            var retval : objType;
            return (false, retval);
          }
          _tail.compareExchange(curr_tail, next_node);
        }
        else {
          var ret_val = next_node.val;
          if (_head.compareExchange(curr_head, next_node)) {
            tok.delete_obj(curr_head);
            tok.unpin();
            return (true, ret_val);
          }
        }
      }

      tok.unpin();
      var retval : objType;
      return (false, retval);
    }

  }

  config const InitialQueueSize = 1024 * 1024;
  config const OperationsPerThread = 1024 * 1024;
  
  use Time;

  proc main() {
    var lfq = new unmanaged ReclaimedLockFreeQueue(int);
    var timer = new Timer();

    // Fill the queue and warm up the cache.
    timer.start();
    forall i in 1..InitialQueueSize with (var tok = lfq.getToken()) do lfq.enqueue(i, tok);
    timer.stop();
    writeln("Queue was initialized to a size of ", InitialQueueSize, " in ", timer.elapsed());
    timer.clear();

    timer.start();
    coforall tid in 1..here.maxTaskPar {
      var tok = lfq.getToken();
      // Even tasks handle enqueue, odd tasks handle dequeue...
      if tid % 2 == 0 {
        for i in 1..OperationsPerThread do lfq.enqueue(i, tok);
      } else {
        for i in 1..OperationsPerThread do lfq.dequeue(tok);
      }
    }
    timer.stop();
    writeln("Performed ", OperationsPerThread, " operations per task with ", here.maxTaskPar, " tasks for a total of ", here.maxTaskPar * OperationsPerThread, " operations in a total of ", timer.elapsed(), "s");
  }
}
