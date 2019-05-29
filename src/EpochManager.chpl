/* Documentation for EpochManager */
module EpochManager {

  class EpochManager {
    const EBR_EPOCHS : uint = 3;
    var global_epoch : atomic uint;
    var allocated_list : LinkedList(unmanaged _token);
    var allocated_list_lock : atomic bool;
    var advance_lock : atomic bool;
    //var limbo_list: LinkedList(unmanaged _deletable);
    var limbo_list : unmanaged _deletable;
    var limbo_list_lock : atomic bool;
    //var epoch_list : [1..EBR_EPOCHS] LinkedList(unmanaged _deletable);
    var epoch_list : [1..EBR_EPOCHS] unmanaged _deletable;
    var id_counter : atomic uint;

    proc init() {
      allocated_list = new LinkedList(unmanaged _token);
      //limbo_list = new LinkedList(unmanaged _deletable);
      limbo_list = nil;
      this.complete();
      global_epoch.write(1);
      /*for i in [1..EBR_EPOCHS] do
        epoch_list[i] = nil;//new LinkedList(unmanaged _deletable);*/
      for i in [1..EBR_EPOCHS] do
        epoch_list[i] = nil;
    }

    proc register() : unmanaged _token { // Should be called only once
      var tok = new unmanaged _token(id_counter.fetchAdd(1));
      while allocated_list_lock.testAndSet() {
        chpl_task_yield(); // yield processor
      }
      allocated_list.append(tok);
      allocated_list_lock.clear();
      return tok;
    }

    proc unregister(tok: unmanaged _token) {
      while allocated_list_lock.testAndSet() {
        chpl_task_yield();
      }
      allocated_list.remove(tok);
      delete tok;
      allocated_list_lock.clear();
    }

    proc pin(tok: unmanaged _token) {
      // An inactive task has local_epoch set to 0. A value other than 0
      // implies active task
      tok.local_epoch.write(global_epoch.read());
    }

    proc unpin(tok: unmanaged _token) {
      tok.local_epoch.write(0);
    }

    // Attempt to announce a new epoch
    proc try_advance() : bool {
      while advance_lock.testAndSet() {
        chpl_task_yield();
      }
      var epoch = global_epoch.read();
      for tok in allocated_list {
        var local_epoch = tok.local_epoch.read();
        if (local_epoch > 0 && local_epoch != epoch) {
          advance_lock.clear();
          return false;
        }
      }

      // Advance the global epoch
      global_epoch.write((epoch % EBR_EPOCHS) + 1);
      advance_lock.clear();
      return true;
    }

    // Return epoch which is safe to be reclaimed
    proc gc_epoch() : uint {
      var epoch = global_epoch.read() : int;
      var ebr_epochs = EBR_EPOCHS : int;

      // It is safe to reclaim from e-2 epoch
      return ((ebr_epochs + (epoch-3) % ebr_epochs):uint % EBR_EPOCHS) + 1;
    }

    proc delete_obj(x) {
      var deletable = new unmanaged _deletable(x);
      while limbo_list_lock.testAndSet() {
        chpl_task_yield();
      }
      //limbo_list.append(deletable);
      if (limbo_list == nil) {
        limbo_list = deletable;
      } else {
        deletable.next = limbo_list;
        limbo_list = deletable;
      }
      limbo_list_lock.clear();
    }

    proc try_reclaim() {
      var count = EBR_EPOCHS;

      // if nothing to reclaim, try the next epoch, but loop only for one
      // full cycle
      while (count) {
        count = count - 1;
        if (!try_advance()) {
          return;
        }

        var staging_epoch = global_epoch.read();
        if (epoch_list[staging_epoch] != nil) {
          writeln("Error: List not empty.");
          //exit();
        }

        while limbo_list_lock.testAndSet() {
          chpl_task_yield();
        }
        epoch_list[staging_epoch] = limbo_list;
        limbo_list = nil;
        limbo_list_lock.clear();

        var gc_list = epoch_list[staging_epoch];
        if (gc_list != nil) {
          _reclaim(gc_list);
          epoch_list[staging_epoch] = nil;
          break;
        }
      }
    }

    proc _reclaim(inout gc_list : unmanaged _deletable) {
      while (gc_list != nil) {
        var x = gc_list;
        gc_list = gc_list.next;
        delete x.p;
        delete x;
      }
    }
  }

  class _token {
    var local_epoch : atomic uint;
    const id : uint;

    proc init(x : uint) {
      id = x;
    }
  }

  class _deletable {
    var p: unmanaged object;
    var next : unmanaged _deletable;

    proc init(x : unmanaged object) {
      p = x;
      next = nil;
    }
  }
}
