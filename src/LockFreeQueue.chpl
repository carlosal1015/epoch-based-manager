module LockFreeQueue {

  use LocalAtomics;

  class LockFreeQueue {
    type objType;
    var _head : LocalAtomicObject(objType);
    var _tail : LocalAtomicObject(objType);

    proc init(type objType) {
      this.objType = objType;
      this.complete();
      var _node = new objType(0);
      _head.write(_node);
      _tail.write(_node);
    }

    proc enqueue(newObj : objType) {
      while (true) {
        var curr_tail = _tail.readABA();
        var next = curr_tail.next.readABA();
        if (next.getObject() == nil) {
          if (curr_tail.next.compareExchangeABA(next, newObj)) {
            _tail.compareExchangeABA(curr_tail, newObj);
            break;
          }
        }
        else {
          _tail.compareExchangeABA(curr_tail, next.getObject());
        }
      }
    }

    proc dequeue() : objType {
      while (true) {
        var curr_head = _head.readABA();
        var curr_tail = _tail.readABA();
        var next = curr_head.next.readABA();
        if (_head.read() == _tail.read()) {
          if (next.getObject() == nil) then
            return nil;
          _tail.compareExchangeABA(curr_tail, next.getObject());
        }
        else {
          if (_head.compareExchangeABA(curr_head, next.getObject())) then
            return next.getObject();
        }
      }
      return nil;
    }

    proc deinit() {
      var ptr = _head.read();
      while (ptr != nil) {
        _head = ptr.next;
        delete ptr;
        ptr = _head.read();
      }
    }
  }

  class node {
    var val : int;
    var next : LocalAtomicObject(unmanaged node);

    proc init(val : int) {
      this.val = val;
    }
  }
}
