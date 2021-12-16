const std = @import("std");

const Signals = enum {};
const SignalQueue = std.fifo.LinearFifo(Signals, .Dynamic);
const Status = enum { Running, Paused, Zombie, Dead };

const Process = struct {
    pid: u16,
    status: Status,
    parent: ?*Process,
    childrens: []*Process,
    signals: SignalQueue,
    owner_id: u16,
};
