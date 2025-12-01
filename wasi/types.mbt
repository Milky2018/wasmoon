///|
/// WASI Error codes (errno)
/// Reference: https://github.com/WebAssembly/WASI/blob/main/legacy/preview1/docs.md#-errno-variant
pub(all) enum Errno {
  /// No error occurred. System call completed successfully.
  Success // 0
  /// Argument list too long.
  TooBig // 1
  /// Permission denied.
  Acces // 2
  /// Address in use.
  AddrInUse // 3
  /// Address not available.
  AddrNotAvail // 4
  /// Address family not supported.
  AfNoSupport // 5
  /// Resource unavailable, or operation would block.
  Again // 6
  /// Connection already in progress.
  Already // 7
  /// Bad file descriptor.
  Badf // 8
  /// Bad message.
  BadMsg // 9
  /// Device or resource busy.
  Busy // 10
  /// Operation canceled.
  Canceled // 11
  /// No child processes.
  Child // 12
  /// Connection aborted.
  ConnAborted // 13
  /// Connection refused.
  ConnRefused // 14
  /// Connection reset.
  ConnReset // 15
  /// Resource deadlock would occur.
  Deadlk // 16
  /// Destination address required.
  DestAddrReq // 17
  /// Mathematics argument out of domain of function.
  Dom // 18
  /// Reserved.
  DQuot // 19
  /// File exists.
  Exist // 20
  /// Bad address.
  Fault // 21
  /// File too large.
  FBig // 22
  /// Host is unreachable.
  HostUnreach // 23
  /// Identifier removed.
  IdRm // 24
  /// Illegal byte sequence.
  IlSeq // 25
  /// Operation in progress.
  InProgress // 26
  /// Interrupted function.
  Intr // 27
  /// Invalid argument.
  Inval // 28
  /// I/O error.
  IO // 29
  /// Socket is connected.
  IsConn // 30
  /// Is a directory.
  IsDir // 31
  /// Too many levels of symbolic links.
  Loop // 32
  /// File descriptor value too large.
  MFile // 33
  /// Too many links.
  MLink // 34
  /// Message too large.
  MsgSize // 35
  /// Reserved.
  MultiHop // 36
  /// Filename too long.
  NameTooLong // 37
  /// Network is down.
  NetDown // 38
  /// Connection aborted by network.
  NetReset // 39
  /// Network unreachable.
  NetUnreach // 40
  /// Too many files open in system.
  NFile // 41
  /// No buffer space available.
  NoBufS // 42
  /// No such device.
  NoDev // 43
  /// No such file or directory.
  NoEnt // 44
  /// Executable file format error.
  NoExec // 45
  /// No locks available.
  NoLck // 46
  /// Reserved.
  NoLink // 47
  /// Not enough space.
  NoMem // 48
  /// No message of the desired type.
  NoMsg // 49
  /// Protocol not available.
  NoProtoOpt // 50
  /// No space left on device.
  NoSpc // 51
  /// Function not supported.
  NoSys // 52
  /// The socket is not connected.
  NotConn // 53
  /// Not a directory or a symbolic link to a directory.
  NotDir // 54
  /// Directory not empty.
  NotEmpty // 55
  /// State not recoverable.
  NotRecoverable // 56
  /// Not a socket.
  NotSock // 57
  /// Not supported, or operation not supported on socket.
  NotSup // 58
  /// Inappropriate I/O control operation.
  NoTTY // 59
  /// No such device or address.
  NxIO // 60
  /// Value too large to be stored in data type.
  Overflow // 61
  /// Previous owner died.
  OwnerDead // 62
  /// Operation not permitted.
  Perm // 63
  /// Broken pipe.
  Pipe // 64
  /// Protocol error.
  Proto // 65
  /// Protocol not supported.
  ProtoNoSupport // 66
  /// Protocol wrong type for socket.
  Prototype // 67
  /// Result too large.
  Range // 68
  /// Read-only file system.
  ROFS // 69
  /// Invalid seek.
  SPipe // 70
  /// No such process.
  SRch // 71
  /// Reserved.
  Stale // 72
  /// Connection timed out.
  TimedOut // 73
  /// Text file busy.
  TxtBsy // 74
  /// Cross-device link.
  XDev // 75
  /// Extension: Capabilities insufficient.
  NotCapable // 76
}

///|
pub fn Errno::to_i32(self : Errno) -> Int {
  match self {
    Success => 0
    TooBig => 1
    Acces => 2
    AddrInUse => 3
    AddrNotAvail => 4
    AfNoSupport => 5
    Again => 6
    Already => 7
    Badf => 8
    BadMsg => 9
    Busy => 10
    Canceled => 11
    Child => 12
    ConnAborted => 13
    ConnRefused => 14
    ConnReset => 15
    Deadlk => 16
    DestAddrReq => 17
    Dom => 18
    DQuot => 19
    Exist => 20
    Fault => 21
    FBig => 22
    HostUnreach => 23
    IdRm => 24
    IlSeq => 25
    InProgress => 26
    Intr => 27
    Inval => 28
    IO => 29
    IsConn => 30
    IsDir => 31
    Loop => 32
    MFile => 33
    MLink => 34
    MsgSize => 35
    MultiHop => 36
    NameTooLong => 37
    NetDown => 38
    NetReset => 39
    NetUnreach => 40
    NFile => 41
    NoBufS => 42
    NoDev => 43
    NoEnt => 44
    NoExec => 45
    NoLck => 46
    NoLink => 47
    NoMem => 48
    NoMsg => 49
    NoProtoOpt => 50
    NoSpc => 51
    NoSys => 52
    NotConn => 53
    NotDir => 54
    NotEmpty => 55
    NotRecoverable => 56
    NotSock => 57
    NotSup => 58
    NoTTY => 59
    NxIO => 60
    Overflow => 61
    OwnerDead => 62
    Perm => 63
    Pipe => 64
    Proto => 65
    ProtoNoSupport => 66
    Prototype => 67
    Range => 68
    ROFS => 69
    SPipe => 70
    SRch => 71
    Stale => 72
    TimedOut => 73
    TxtBsy => 74
    XDev => 75
    NotCapable => 76
  }
}

///|
/// File descriptor type
pub(all) struct Fd(Int) derive(Eq, Show)

///|
/// Standard file descriptors
pub let stdin : Fd = Fd(0)

///|
pub let stdout : Fd = Fd(1)

///|
pub let stderr : Fd = Fd(2)

///|
pub fn Fd::to_int(self : Fd) -> Int {
  self.0
}

///|
pub fn Fd::from_int(n : Int) -> Fd {
  Fd(n)
}

///|
/// Clock identifiers
pub(all) enum ClockId {
  /// Wall clock time
  Realtime // 0
  /// Monotonic clock
  Monotonic // 1
  /// CPU time of the current process
  ProcessCPUTimeId // 2
  /// CPU time of the current thread
  ThreadCPUTimeId // 3
}

///|
pub fn ClockId::from_i32(n : Int) -> ClockId? {
  match n {
    0 => Some(Realtime)
    1 => Some(Monotonic)
    2 => Some(ProcessCPUTimeId)
    3 => Some(ThreadCPUTimeId)
    _ => None
  }
}

///|
/// Timestamp in nanoseconds
pub(all) struct Timestamp(Int64) derive(Show, Eq)

///|
pub fn Timestamp::to_int64(self : Timestamp) -> Int64 {
  self.0
}

///|
/// Size type (corresponds to wasi size)
pub(all) struct Size(Int) derive(Show, Eq)

///|
pub fn Size::to_int(self : Size) -> Int {
  self.0
}

///|
/// File size type
pub(all) struct FileSize(Int64) derive(Show, Eq)

///|
pub fn FileSize::to_int64(self : FileSize) -> Int64 {
  self.0
}

///|
/// iovec structure for scatter/gather I/O
pub(all) struct IoVec {
  /// Pointer to buffer in WASM memory
  buf : Int
  /// Length of buffer
  buf_len : Int
}

///|
/// ciovec structure (const iovec)
pub(all) struct CIoVec {
  /// Pointer to buffer in WASM memory
  buf : Int
  /// Length of buffer
  buf_len : Int
}
